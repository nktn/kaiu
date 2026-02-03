const std = @import("std");
const builtin = @import("builtin");

// =============================================================================
// JSON-RPC 2.0 Message Types (T004)
// =============================================================================

/// JSON-RPC request message.
pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: u32,
    method: []const u8,
    params: ?std.json.Value = null,
};

/// JSON-RPC response message.
pub const JsonRpcResponse = struct {
    jsonrpc: []const u8,
    id: ?u32,
    result: ?std.json.Value,
    @"error": ?JsonRpcError,
};

/// JSON-RPC error object.
pub const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?std.json.Value = null,
};

/// JSON-RPC notification (no id, no response expected).
pub const JsonRpcNotification = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?std.json.Value = null,
};

// LSP standard error codes
pub const LspErrorCode = struct {
    pub const parse_error: i32 = -32700;
    pub const invalid_request: i32 = -32600;
    pub const method_not_found: i32 = -32601;
    pub const invalid_params: i32 = -32602;
    pub const internal_error: i32 = -32603;
    pub const server_not_initialized: i32 = -32002;
    pub const unknown_error_code: i32 = -32001;
    pub const request_cancelled: i32 = -32800;
    pub const content_modified: i32 = -32801;
};

/// Content-Length header prefix for LSP messages.
const CONTENT_LENGTH_HEADER = "Content-Length: ";
const HEADER_DELIMITER = "\r\n\r\n";

/// LSP message timeout in nanoseconds (3 seconds per SC-002).
pub const LSP_TIMEOUT_NS: u64 = 3 * std.time.ns_per_s;

/// Maximum LSP message size (10 MB).
const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024;

/// LSP client for communicating with language servers (e.g., zls) via JSON-RPC over stdio.
///
/// Lifecycle:
/// 1. init() - Create client instance
/// 2. start() - Launch language server process and complete handshake
/// 3. findReferences() / getIncomingCalls() / getOutgoingCalls() - Send requests
/// 4. stop() - Terminate language server process
/// 5. deinit() - Clean up resources
pub const LspClient = struct {
    allocator: std.mem.Allocator,
    process: ?std.process.Child,
    stdin: ?std.fs.File,
    stdout: ?std.fs.File,
    request_id: u32,
    root_path: ?[]const u8,
    initialized: bool,
    read_buffer: std.ArrayList(u8),
    last_parsed: ?std.json.Parsed(std.json.Value),

    pub const Error = error{
        ServerNotFound,
        ServerNotRunning,
        RequestTimeout,
        InvalidResponse,
        OutOfMemory,
        ProcessSpawnFailed,
        HandshakeFailed,
        IoError,
    };

    /// Initialize LSP client. Does not start the server. (T005)
    pub fn init(allocator: std.mem.Allocator) LspClient {
        return .{
            .allocator = allocator,
            .process = null,
            .stdin = null,
            .stdout = null,
            .request_id = 0,
            .root_path = null,
            .initialized = false,
            .read_buffer = .empty,
            .last_parsed = null,
        };
    }

    /// Clean up resources. (T005)
    pub fn deinit(self: *LspClient) void {
        // Free last parsed result if any
        if (self.last_parsed) |*prev| {
            prev.deinit();
            self.last_parsed = null;
        }
        self.stop();
        if (self.root_path) |path| {
            self.allocator.free(path);
            self.root_path = null;
        }
        self.read_buffer.deinit(self.allocator);
    }

    /// Start the language server and complete the initialize handshake. (T006, T008)
    pub fn start(self: *LspClient, root_path: []const u8) Error!void {
        if (self.process != null) {
            self.stop();
        }

        // Store root path
        self.root_path = self.allocator.dupe(u8, root_path) catch return Error.OutOfMemory;
        errdefer {
            if (self.root_path) |p| {
                self.allocator.free(p);
                self.root_path = null;
            }
        }

        // Find zls executable (T006)
        const zls_path = findZlsExecutable() orelse return Error.ServerNotFound;

        // Spawn zls process with stdio pipes (T006)
        var child = std.process.Child.init(&[_][]const u8{zls_path}, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return Error.ProcessSpawnFailed;
        errdefer {
            _ = child.kill() catch {};
            _ = child.wait() catch {};
        }

        self.stdin = child.stdin;
        self.stdout = child.stdout;
        self.process = child;

        // Complete initialize handshake (T008)
        self.performHandshake() catch return Error.HandshakeFailed;
        self.initialized = true;
    }

    /// Stop the language server process. (T005)
    pub fn stop(self: *LspClient) void {
        if (self.process) |*proc| {
            // Send shutdown request if initialized
            if (self.initialized) {
                self.sendShutdown() catch {};
                self.sendExit() catch {};
            }

            // Close pipes
            if (self.stdin) |stdin| {
                stdin.close();
                self.stdin = null;
            }
            if (self.stdout) |stdout| {
                stdout.close();
                self.stdout = null;
            }

            // Wait for process to exit (avoid zombies)
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};
            self.process = null;
        }
        self.initialized = false;
    }

    /// Check if server is running and initialized.
    pub fn isRunning(self: *const LspClient) bool {
        return self.process != null and self.initialized;
    }

    /// Send textDocument/references request (US1: Reference list). (T012)
    pub fn findReferences(
        self: *LspClient,
        file_path: []const u8,
        line: u32,
        column: u32,
    ) Error![]SymbolReference {
        if (!self.isRunning()) return Error.ServerNotRunning;

        const uri = pathToUri(self.allocator, file_path) catch return Error.OutOfMemory;
        defer self.allocator.free(uri);

        // Build textDocument/references params
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        // textDocument
        var text_document = std.json.ObjectMap.init(self.allocator);
        defer text_document.deinit();
        text_document.put("uri", std.json.Value{ .string = uri }) catch return Error.OutOfMemory;
        params.put("textDocument", std.json.Value{ .object = text_document }) catch return Error.OutOfMemory;

        // position (LSP uses 0-indexed)
        var position = std.json.ObjectMap.init(self.allocator);
        defer position.deinit();
        position.put("line", std.json.Value{ .integer = @intCast(line) }) catch return Error.OutOfMemory;
        position.put("character", std.json.Value{ .integer = @intCast(column) }) catch return Error.OutOfMemory;
        params.put("position", std.json.Value{ .object = position }) catch return Error.OutOfMemory;

        // context (includeDeclaration)
        var context = std.json.ObjectMap.init(self.allocator);
        defer context.deinit();
        context.put("includeDeclaration", std.json.Value{ .bool = true }) catch return Error.OutOfMemory;
        params.put("context", std.json.Value{ .object = context }) catch return Error.OutOfMemory;

        // Send request
        const response = self.sendRequest("textDocument/references", std.json.Value{ .object = params }) catch return Error.InvalidResponse;

        // Parse response
        return self.parseReferencesResponse(response);
    }

    /// Parse textDocument/references response into SymbolReference array. (T012)
    fn parseReferencesResponse(self: *LspClient, response: std.json.Value) Error![]SymbolReference {
        // Response should be an array of Location objects or null
        if (response == .null) {
            return &[_]SymbolReference{};
        }

        const locations = switch (response) {
            .array => |arr| arr.items,
            else => return &[_]SymbolReference{},
        };

        if (locations.len == 0) {
            return &[_]SymbolReference{};
        }

        var refs: std.ArrayList(SymbolReference) = .empty;
        errdefer {
            for (refs.items) |*ref| {
                self.allocator.free(ref.file_path);
                self.allocator.free(ref.snippet);
            }
            refs.deinit(self.allocator);
        }

        for (locations) |loc| {
            const loc_obj = switch (loc) {
                .object => |obj| obj,
                else => continue,
            };

            // Get URI and convert to path
            const uri_val = loc_obj.get("uri") orelse continue;
            const uri = switch (uri_val) {
                .string => |s| s,
                else => continue,
            };
            const path = uriToPath(self.allocator, uri) catch continue;
            errdefer self.allocator.free(path);

            // Get range.start position
            const range_val = loc_obj.get("range") orelse continue;
            const range = switch (range_val) {
                .object => |obj| obj,
                else => continue,
            };
            const start_val = range.get("start") orelse continue;
            const start_pos = switch (start_val) {
                .object => |obj| obj,
                else => continue,
            };

            const line_val = start_pos.get("line") orelse continue;
            const line: u32 = switch (line_val) {
                .integer => |i| if (i >= 0 and i <= std.math.maxInt(u32)) @intCast(i) else continue,
                else => continue,
            };
            const char_val = start_pos.get("character") orelse continue;
            const column: u32 = switch (char_val) {
                .integer => |i| if (i >= 0 and i <= std.math.maxInt(u32)) @intCast(i) else continue,
                else => continue,
            };

            // Read snippet from file
            const snippet = readSnippetFromFile(self.allocator, path, line) catch
                self.allocator.dupe(u8, "") catch continue;

            refs.append(self.allocator, .{
                .file_path = path,
                .line = line,
                .column = column,
                .snippet = snippet,
            }) catch {
                self.allocator.free(path);
                self.allocator.free(snippet);
                continue;
            };
        }

        return refs.toOwnedSlice(self.allocator) catch return Error.OutOfMemory;
    }

    /// Send textDocument/prepareCallHierarchy request. (T024)
    /// Returns the CallHierarchyItem for the symbol at the given position.
    fn prepareCallHierarchy(self: *LspClient, file_path: []const u8, line: u32, column: u32) Error!?std.json.Value {
        if (!self.isRunning()) return Error.ServerNotRunning;

        const uri = pathToUri(self.allocator, file_path) catch return Error.OutOfMemory;
        defer self.allocator.free(uri);

        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        // textDocumentIdentifier
        var text_document = std.json.ObjectMap.init(self.allocator);
        defer text_document.deinit();
        text_document.put("uri", std.json.Value{ .string = uri }) catch return Error.OutOfMemory;
        params.put("textDocument", std.json.Value{ .object = text_document }) catch return Error.OutOfMemory;

        // position
        var position = std.json.ObjectMap.init(self.allocator);
        defer position.deinit();
        position.put("line", std.json.Value{ .integer = @intCast(line) }) catch return Error.OutOfMemory;
        position.put("character", std.json.Value{ .integer = @intCast(column) }) catch return Error.OutOfMemory;
        params.put("position", std.json.Value{ .object = position }) catch return Error.OutOfMemory;

        // Send request
        const response = self.sendRequest("textDocument/prepareCallHierarchy", std.json.Value{ .object = params }) catch return Error.InvalidResponse;

        // Response is array of CallHierarchyItem or null
        if (response == .null) return null;

        const items = switch (response) {
            .array => |arr| arr.items,
            else => return null,
        };

        if (items.len == 0) return null;

        // Return the first item (the symbol at cursor)
        return items[0];
    }

    /// Send callHierarchy/prepareCallHierarchy + incomingCalls request (US2: Incoming calls). (T024b)
    pub fn getIncomingCalls(
        self: *LspClient,
        file_path: []const u8,
        line: u32,
        column: u32,
    ) Error![]CallHierarchyItem {
        if (!self.isRunning()) return Error.ServerNotRunning;

        // First, get the CallHierarchyItem for the symbol
        const prepare_result = try self.prepareCallHierarchy(file_path, line, column);
        const item = prepare_result orelse return &[_]CallHierarchyItem{};

        // Now request incoming calls
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();
        params.put("item", item) catch return Error.OutOfMemory;

        const response = self.sendRequest("callHierarchy/incomingCalls", std.json.Value{ .object = params }) catch return Error.InvalidResponse;

        return self.parseCallHierarchyResponse(response, true);
    }

    /// Send callHierarchy/prepareCallHierarchy + outgoingCalls request (US2: Outgoing calls). (T024c)
    pub fn getOutgoingCalls(
        self: *LspClient,
        file_path: []const u8,
        line: u32,
        column: u32,
    ) Error![]CallHierarchyItem {
        if (!self.isRunning()) return Error.ServerNotRunning;

        // First, get the CallHierarchyItem for the symbol
        const prepare_result = try self.prepareCallHierarchy(file_path, line, column);
        const item = prepare_result orelse return &[_]CallHierarchyItem{};

        // Now request outgoing calls
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();
        params.put("item", item) catch return Error.OutOfMemory;

        const response = self.sendRequest("callHierarchy/outgoingCalls", std.json.Value{ .object = params }) catch return Error.InvalidResponse;

        return self.parseCallHierarchyResponse(response, false);
    }

    /// Parse callHierarchy/incomingCalls or outgoingCalls response.
    fn parseCallHierarchyResponse(self: *LspClient, response: std.json.Value, is_incoming: bool) Error![]CallHierarchyItem {
        if (response == .null) return &[_]CallHierarchyItem{};

        const items = switch (response) {
            .array => |arr| arr.items,
            else => return &[_]CallHierarchyItem{},
        };

        if (items.len == 0) return &[_]CallHierarchyItem{};

        var result: std.ArrayList(CallHierarchyItem) = .empty;
        errdefer {
            for (result.items) |*item| {
                self.allocator.free(item.name);
                self.allocator.free(item.file_path);
                self.allocator.free(item.snippet);
            }
            result.deinit(self.allocator);
        }

        for (items) |call_item| {
            const call_obj = switch (call_item) {
                .object => |obj| obj,
                else => continue,
            };

            // For incoming calls, the caller is in "from" field
            // For outgoing calls, the callee is in "to" field
            const field_name = if (is_incoming) "from" else "to";
            const hierarchy_item = call_obj.get(field_name) orelse continue;
            const item_obj = switch (hierarchy_item) {
                .object => |obj| obj,
                else => continue,
            };

            // Extract name
            const name = switch (item_obj.get("name") orelse continue) {
                .string => |s| s,
                else => continue,
            };

            // Extract kind
            const kind_val: u8 = switch (item_obj.get("kind") orelse continue) {
                .integer => |i| if (i >= 0 and i <= 255) @intCast(i) else continue,
                else => continue,
            };
            const kind = SymbolKind.fromInt(kind_val) orelse continue;

            // Extract URI and convert to path
            const uri = switch (item_obj.get("uri") orelse continue) {
                .string => |s| s,
                else => continue,
            };
            const path = uriToPath(self.allocator, uri) catch continue;
            errdefer self.allocator.free(path);

            // Extract range for line/column
            const range = switch (item_obj.get("range") orelse continue) {
                .object => |obj| obj,
                else => continue,
            };
            const range_start = switch (range.get("start") orelse continue) {
                .object => |obj| obj,
                else => continue,
            };
            const line_val: u32 = switch (range_start.get("line") orelse continue) {
                .integer => |i| if (i >= 0 and i <= std.math.maxInt(u32)) @intCast(i) else continue,
                else => continue,
            };
            const col_val: u32 = switch (range_start.get("character") orelse continue) {
                .integer => |i| if (i >= 0 and i <= std.math.maxInt(u32)) @intCast(i) else continue,
                else => continue,
            };

            // Read snippet from file
            const snippet = readSnippetFromFile(self.allocator, path, line_val) catch
                self.allocator.dupe(u8, "") catch continue;

            const name_dupe = self.allocator.dupe(u8, name) catch continue;
            errdefer self.allocator.free(name_dupe);

            result.append(self.allocator, .{
                .name = name_dupe,
                .kind = kind,
                .file_path = path,
                .line = line_val,
                .column = col_val,
                .snippet = snippet,
            }) catch {
                self.allocator.free(name_dupe);
                self.allocator.free(path);
                self.allocator.free(snippet);
                continue;
            };
        }

        return result.toOwnedSlice(self.allocator) catch return Error.OutOfMemory;
    }

    /// Send textDocument/didOpen notification. (T009)
    pub fn didOpen(self: *LspClient, file_path: []const u8, content: []const u8) Error!void {
        if (!self.isRunning()) return Error.ServerNotRunning;

        const uri = pathToUri(self.allocator, file_path) catch return Error.OutOfMemory;
        defer self.allocator.free(uri);

        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        var text_document = std.json.ObjectMap.init(self.allocator);
        defer text_document.deinit();

        text_document.put("uri", std.json.Value{ .string = uri }) catch return Error.OutOfMemory;
        text_document.put("languageId", std.json.Value{ .string = "zig" }) catch return Error.OutOfMemory;
        text_document.put("version", std.json.Value{ .integer = 1 }) catch return Error.OutOfMemory;
        text_document.put("text", std.json.Value{ .string = content }) catch return Error.OutOfMemory;

        params.put("textDocument", std.json.Value{ .object = text_document }) catch return Error.OutOfMemory;

        self.sendNotification("textDocument/didOpen", std.json.Value{ .object = params }) catch return Error.IoError;
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    /// Perform initialize / initialized handshake. (T008)
    fn performHandshake(self: *LspClient) !void {
        const root_uri = pathToUri(self.allocator, self.root_path.?) catch return error.OutOfMemory;
        defer self.allocator.free(root_uri);

        // Build initialize params
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        params.put("processId", std.json.Value{ .integer = @intCast(std.c.getpid()) }) catch return error.OutOfMemory;
        params.put("rootUri", std.json.Value{ .string = root_uri }) catch return error.OutOfMemory;

        // Client capabilities
        var capabilities = std.json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();
        params.put("capabilities", std.json.Value{ .object = capabilities }) catch return error.OutOfMemory;

        // Send initialize request
        const response = try self.sendRequest("initialize", std.json.Value{ .object = params });
        _ = response; // We don't need the result for now

        // Send initialized notification
        try self.sendNotification("initialized", null);
    }

    /// Send shutdown request.
    fn sendShutdown(self: *LspClient) !void {
        _ = try self.sendRequest("shutdown", null);
    }

    /// Send exit notification.
    fn sendExit(self: *LspClient) !void {
        try self.sendNotification("exit", null);
    }

    /// Send a JSON-RPC request and wait for response. (T007)
    fn sendRequest(self: *LspClient, method: []const u8, params: ?std.json.Value) !std.json.Value {
        const id = self.request_id;
        self.request_id += 1;

        // Build request JSON
        var request_obj = std.json.ObjectMap.init(self.allocator);
        defer request_obj.deinit();

        request_obj.put("jsonrpc", std.json.Value{ .string = "2.0" }) catch return error.OutOfMemory;
        request_obj.put("id", std.json.Value{ .integer = @intCast(id) }) catch return error.OutOfMemory;
        request_obj.put("method", std.json.Value{ .string = method }) catch return error.OutOfMemory;
        if (params) |p| {
            request_obj.put("params", p) catch return error.OutOfMemory;
        }

        // Serialize to JSON using std.io.Writer.Allocating and std.json.Stringify
        var out: std.io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer };
        jw.write(std.json.Value{ .object = request_obj }) catch return error.OutOfMemory;
        const json_str = out.written();

        // Send message
        try self.sendMessage(json_str);

        // Read response
        return self.readResponse(id);
    }

    /// Send a JSON-RPC notification (no response expected). (T007)
    fn sendNotification(self: *LspClient, method: []const u8, params: ?std.json.Value) !void {
        var notif_obj = std.json.ObjectMap.init(self.allocator);
        defer notif_obj.deinit();

        notif_obj.put("jsonrpc", std.json.Value{ .string = "2.0" }) catch return error.OutOfMemory;
        notif_obj.put("method", std.json.Value{ .string = method }) catch return error.OutOfMemory;
        if (params) |p| {
            notif_obj.put("params", p) catch return error.OutOfMemory;
        }

        // Serialize to JSON using std.io.Writer.Allocating and std.json.Stringify
        var out: std.io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer };
        jw.write(std.json.Value{ .object = notif_obj }) catch return error.OutOfMemory;

        try self.sendMessage(out.written());
    }

    /// Send a message with Content-Length header. (T007)
    fn sendMessage(self: *LspClient, content: []const u8) !void {
        const stdin = self.stdin orelse return error.ServerNotRunning;

        // Write header
        var header_buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{content.len}) catch return error.InvalidResponse;

        stdin.writeAll(header) catch return error.IoError;
        stdin.writeAll(content) catch return error.IoError;
    }

    /// Read a response with the given request ID. (T007)
    fn readResponse(self: *LspClient, expected_id: u32) !std.json.Value {
        const stdout = self.stdout orelse return error.ServerNotRunning;

        // Read until we find a response with matching ID
        while (true) {
            // Read Content-Length header
            const content_length = try self.readContentLength(stdout);
            if (content_length > MAX_MESSAGE_SIZE) return error.InvalidResponse;

            // Read content
            self.read_buffer.clearRetainingCapacity();
            try self.read_buffer.resize(self.allocator, content_length);

            const bytes_read = stdout.readAll(self.read_buffer.items) catch return error.IoError;
            if (bytes_read != content_length) return error.InvalidResponse;

            // Parse JSON
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, self.read_buffer.items, .{}) catch return error.InvalidResponse;
            // Free previous parsed result
            if (self.last_parsed) |*prev| {
                prev.deinit();
            }
            // Store parsed result to keep memory alive
            self.last_parsed = parsed;

            // Check if this is our response
            if (parsed.value.object.get("id")) |id_val| {
                switch (id_val) {
                    .integer => |id| {
                        if (id == expected_id) {
                            // Check for error
                            if (parsed.value.object.get("error")) |_| {
                                return error.InvalidResponse;
                            }
                            // Return result
                            if (parsed.value.object.get("result")) |result| {
                                return result;
                            }
                            return std.json.Value.null;
                        }
                    },
                    else => {},
                }
            }
            // Not our response (notification or different ID), continue reading
        }
    }

    /// Read Content-Length header value.
    fn readContentLength(self: *LspClient, file: std.fs.File) !usize {
        _ = self;
        var header_buf: [256]u8 = undefined;
        var header_len: usize = 0;
        var byte_buf: [1]u8 = undefined;

        // Read header until we find \r\n\r\n
        while (header_len < header_buf.len - 1) {
            const bytes_read = file.read(&byte_buf) catch return error.IoError;
            if (bytes_read == 0) return error.IoError;
            header_buf[header_len] = byte_buf[0];
            header_len += 1;

            // Check for end of header
            if (header_len >= 4) {
                const end = header_buf[header_len - 4 .. header_len];
                if (std.mem.eql(u8, end, "\r\n\r\n")) {
                    break;
                }
            }
        }

        const header_str = header_buf[0..header_len];

        // Find Content-Length value
        if (std.mem.indexOf(u8, header_str, CONTENT_LENGTH_HEADER)) |idx| {
            const value_start = idx + CONTENT_LENGTH_HEADER.len;
            const value_end = std.mem.indexOf(u8, header_str[value_start..], "\r\n") orelse return error.InvalidResponse;
            const len_str = header_str[value_start .. value_start + value_end];
            return std.fmt.parseInt(usize, len_str, 10) catch return error.InvalidResponse;
        }

        return error.InvalidResponse;
    }
};

/// Find zls executable in PATH. (T010)
fn findZlsExecutable() ?[]const u8 {
    // Check if zls is in PATH
    const path_env = std.posix.getenv("PATH") orelse return null;

    var path_iter = std.mem.splitScalar(u8, path_env, ':');
    while (path_iter.next()) |dir| {
        // Try to access zls in this directory
        const check_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ dir, "zls" }) catch continue;
        defer std.heap.page_allocator.free(check_path);

        std.fs.accessAbsolute(check_path, .{}) catch continue;
        return "zls"; // Return just the name, let Child.init find it
    }

    return null;
}

/// Convert file path to file:// URI.
fn pathToUri(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "file://{s}", .{path});
}

/// Convert file:// URI to file path.
fn uriToPath(allocator: std.mem.Allocator, uri: []const u8) ![]const u8 {
    const prefix = "file://";
    if (std.mem.startsWith(u8, uri, prefix)) {
        return allocator.dupe(u8, uri[prefix.len..]);
    }
    return allocator.dupe(u8, uri);
}

/// Read a single line from a file at the given line number (0-indexed).
fn readSnippetFromFile(allocator: std.mem.Allocator, path: []const u8, line: u32) ![]const u8 {
    // Read the entire file and split by lines (limit to 1MB for snippet extraction)
    const content = std.fs.cwd().readFileAlloc(allocator, path, 1 * 1024 * 1024) catch {
        return allocator.dupe(u8, "");
    };
    defer allocator.free(content);

    var line_count: u32 = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line_data| {
        if (line_count == line) {
            // Trim trailing whitespace (including \r for CRLF)
            var end = line_data.len;
            while (end > 0 and (line_data[end - 1] == ' ' or line_data[end - 1] == '\t' or line_data[end - 1] == '\r')) {
                end -= 1;
            }
            return allocator.dupe(u8, line_data[0..end]);
        }
        line_count += 1;
    }

    return allocator.dupe(u8, "");
}

/// Symbol reference location returned from textDocument/references.
pub const SymbolReference = struct {
    file_path: []const u8,
    line: u32,
    column: u32,
    snippet: []const u8,
};

/// Call hierarchy item for graph visualization.
pub const CallHierarchyItem = struct {
    name: []const u8,
    kind: SymbolKind,
    file_path: []const u8,
    line: u32,
    column: u32,
    snippet: []const u8,
};

/// LSP SymbolKind enum (subset of full LSP spec).
pub const SymbolKind = enum(u8) {
    file = 1,
    module = 2,
    namespace = 3,
    package = 4,
    class = 5,
    method = 6,
    property = 7,
    field = 8,
    constructor = 9,
    enum_kind = 10,
    interface = 11,
    function = 12,
    variable = 13,
    constant = 14,
    string = 15,
    number = 16,
    boolean = 17,
    array = 18,
    object = 19,
    key = 20,
    null_kind = 21,
    enum_member = 22,
    struct_kind = 23,
    event = 24,
    operator = 25,
    type_parameter = 26,

    pub fn fromInt(value: u8) ?SymbolKind {
        return std.meta.intToEnum(SymbolKind, value) catch null;
    }
};

// =============================================================================
// Tests (T011)
// =============================================================================

test "LspClient init and deinit" {
    const allocator = std.testing.allocator;
    var client = LspClient.init(allocator);
    defer client.deinit();

    try std.testing.expect(client.process == null);
    try std.testing.expect(client.stdin == null);
    try std.testing.expect(client.stdout == null);
    try std.testing.expect(!client.initialized);
    try std.testing.expectEqual(@as(u32, 0), client.request_id);
}

test "LspClient isRunning returns false when not started" {
    const allocator = std.testing.allocator;
    var client = LspClient.init(allocator);
    defer client.deinit();

    try std.testing.expect(!client.isRunning());
}

test "SymbolKind fromInt" {
    try std.testing.expectEqual(SymbolKind.function, SymbolKind.fromInt(12).?);
    try std.testing.expectEqual(SymbolKind.method, SymbolKind.fromInt(6).?);
    try std.testing.expect(SymbolKind.fromInt(0) == null);
    try std.testing.expect(SymbolKind.fromInt(255) == null);
}

test "pathToUri converts path to file URI" {
    const allocator = std.testing.allocator;
    const uri = try pathToUri(allocator, "/home/user/test.zig");
    defer allocator.free(uri);

    try std.testing.expectEqualStrings("file:///home/user/test.zig", uri);
}

test "JSON-RPC request serialization" {
    const allocator = std.testing.allocator;

    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();
    try params.put("test", std.json.Value{ .string = "value" });

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    try request_obj.put("jsonrpc", std.json.Value{ .string = "2.0" });
    try request_obj.put("id", std.json.Value{ .integer = 1 });
    try request_obj.put("method", std.json.Value{ .string = "test/method" });
    try request_obj.put("params", std.json.Value{ .object = params });

    // Serialize using std.io.Writer.Allocating and std.json.Stringify
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer };
    try jw.write(std.json.Value{ .object = request_obj });
    const json_str = out.written();

    // Verify it contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"method\":\"test/method\"") != null);
}

test "JSON-RPC response parsing" {
    const allocator = std.testing.allocator;

    const json_str =
        \\{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    // Verify we can access fields
    const jsonrpc = parsed.value.object.get("jsonrpc").?.string;
    try std.testing.expectEqualStrings("2.0", jsonrpc);

    const id = parsed.value.object.get("id").?.integer;
    try std.testing.expectEqual(@as(i64, 1), id);

    const result = parsed.value.object.get("result").?;
    try std.testing.expect(result == .object);
}

test "JSON-RPC notification serialization" {
    const allocator = std.testing.allocator;

    var notif_obj = std.json.ObjectMap.init(allocator);
    defer notif_obj.deinit();

    try notif_obj.put("jsonrpc", std.json.Value{ .string = "2.0" });
    try notif_obj.put("method", std.json.Value{ .string = "initialized" });

    // Serialize using std.io.Writer.Allocating and std.json.Stringify
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer };
    try jw.write(std.json.Value{ .object = notif_obj });
    const json_str = out.written();

    // Notifications should NOT have an id field
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"id\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"method\":\"initialized\"") != null);
}

test "LspErrorCode values" {
    try std.testing.expectEqual(@as(i32, -32700), LspErrorCode.parse_error);
    try std.testing.expectEqual(@as(i32, -32600), LspErrorCode.invalid_request);
    try std.testing.expectEqual(@as(i32, -32601), LspErrorCode.method_not_found);
    try std.testing.expectEqual(@as(i32, -32602), LspErrorCode.invalid_params);
    try std.testing.expectEqual(@as(i32, -32603), LspErrorCode.internal_error);
    try std.testing.expectEqual(@as(i32, -32002), LspErrorCode.server_not_initialized);
    try std.testing.expectEqual(@as(i32, -32800), LspErrorCode.request_cancelled);
}
