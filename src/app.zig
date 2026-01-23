const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const ui = @import("ui.zig");

pub const AppMode = enum {
    tree_view,
    preview,
    search,
    path_input,
    help,
};

pub const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
};

/// Pending key for multi-key commands (e.g., 'g' for gg/gn)
const PendingKey = struct {
    key: ?u21,
    timestamp: i64,

    const timeout_ms: i64 = 500;

    fn set(self: *PendingKey, k: u21) void {
        self.key = k;
        self.timestamp = std.time.milliTimestamp();
    }

    fn clear(self: *PendingKey) void {
        self.key = null;
    }

    fn isExpired(self: *const PendingKey) bool {
        if (self.key == null) return true;
        const now = std.time.milliTimestamp();
        return (now - self.timestamp) > timeout_ms;
    }

    fn get(self: *PendingKey) ?u21 {
        if (self.isExpired()) {
            self.clear();
            return null;
        }
        return self.key;
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    file_tree: ?*tree.FileTree,
    mode: AppMode,
    cursor: usize,
    scroll_offset: usize,
    show_hidden: bool,
    last_wheel_time: i64,
    preview_content: ?[]const u8,
    preview_path: ?[]const u8,
    preview_scroll: usize,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    loop: vaxis.Loop(Event),
    tty_buf: [4096]u8,
    render_arena: std.heap.ArenaAllocator,

    // Multi-key command state
    pending_key: PendingKey,

    // Status message (for feedback like "Copied: ...")
    status_message: ?[]const u8,

    // Input buffer for search/path input modes
    input_buffer: std.ArrayList(u8),

    // Search state
    search_query: ?[]const u8,
    search_matches: std.ArrayList(usize), // indices of matching entries
    current_match: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .file_tree = null,
            .mode = .tree_view,
            .cursor = 0,
            .scroll_offset = 0,
            .show_hidden = false,
            .last_wheel_time = 0,
            .preview_content = null,
            .preview_path = null,
            .preview_scroll = 0,
            .should_quit = false,
            .tty = undefined,
            .vx = undefined,
            .render_arena = std.heap.ArenaAllocator.init(allocator),
            .loop = undefined,
            .tty_buf = undefined,
            .pending_key = .{ .key = null, .timestamp = 0 },
            .status_message = null,
            .input_buffer = .empty,
            .search_query = null,
            .search_matches = .empty,
            .current_match = 0,
        };

        self.tty = try vaxis.Tty.init(&self.tty_buf);
        errdefer self.tty.deinit();

        self.vx = try vaxis.Vaxis.init(allocator, .{});
        errdefer self.vx.deinit(allocator, self.tty.writer());

        self.loop = .{ .tty = &self.tty, .vaxis = &self.vx };
        try self.loop.init();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.loop.stop();
        self.vx.deinit(self.allocator, self.tty.writer());
        self.tty.deinit();
        if (self.file_tree) |ft| {
            ft.deinit();
        }
        if (self.preview_content) |content| {
            self.allocator.free(content);
        }
        if (self.preview_path) |path| {
            self.allocator.free(path);
        }
        if (self.search_query) |query| {
            self.allocator.free(query);
        }
        self.input_buffer.deinit(self.allocator);
        self.search_matches.deinit(self.allocator);
        self.render_arena.deinit();
        self.allocator.destroy(self);
    }

    pub fn runEventLoop(self: *Self) !void {
        const writer = self.tty.writer();

        // Enter alt screen
        try self.vx.enterAltScreen(writer);
        errdefer self.vx.exitAltScreen(writer) catch {};

        // Enable mouse mode for wheel events
        try self.vx.setMouseMode(writer, true);
        errdefer self.vx.setMouseMode(writer, false) catch {};

        self.vx.queueRefresh();

        // Start the input thread
        try self.loop.start();
        errdefer self.loop.stop();

        // Initial render
        try self.render(writer);
        try writer.flush();

        // Event loop
        while (!self.should_quit) {
            const event = self.loop.nextEvent();

            switch (event) {
                .key_press => |key| {
                    try self.handleKey(key);
                },
                .mouse => |mouse| {
                    self.handleMouse(mouse);
                },
                .winsize => |ws| {
                    try self.vx.resize(self.allocator, writer, ws);
                },
            }

            // Render after each event
            try self.render(writer);
            try writer.flush();
        }

        // Stop the input thread
        self.loop.stop();

        // Leave alt screen
        try self.vx.exitAltScreen(writer);
        try writer.flush();
    }

    fn handleKey(self: *Self, key: vaxis.Key) !void {
        const key_char = key.codepoint;

        // Clear status message on any key press
        self.status_message = null;

        switch (self.mode) {
            .tree_view => try self.handleTreeViewKey(key_char),
            .preview => self.handlePreviewKey(key_char),
            .search => try self.handleSearchKey(key, key_char),
            .path_input => try self.handlePathInputKey(key, key_char),
            .help => self.handleHelpKey(),
        }
    }

    fn handleMouse(self: *Self, mouse: vaxis.Mouse) void {
        // Debounce wheel events - only process first event in a batch
        const now = std.time.milliTimestamp();
        const wheel_debounce_ms: i64 = 50; // Ignore events within 50ms

        switch (mouse.button) {
            .wheel_up, .wheel_down => {
                if (now - self.last_wheel_time < wheel_debounce_ms) {
                    return; // Skip duplicate wheel events
                }
                self.last_wheel_time = now;
            },
            else => {},
        }

        // Handle mouse wheel scroll
        switch (mouse.button) {
            .wheel_up => {
                switch (self.mode) {
                    .tree_view, .search, .path_input => self.moveCursor(-1),
                    .preview => if (self.preview_scroll > 0) {
                        self.preview_scroll -= 1;
                    },
                    else => {},
                }
            },
            .wheel_down => {
                switch (self.mode) {
                    .tree_view, .search, .path_input => self.moveCursor(1),
                    .preview => self.scrollPreviewDown(self.vx.window().height),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn handleTreeViewKey(self: *Self, key_char: u21) !void {
        // Check for pending multi-key command
        if (self.pending_key.get()) |pending| {
            self.pending_key.clear();

            if (pending == 'g') {
                switch (key_char) {
                    'g' => {
                        // gg - jump to top
                        self.jumpToTop();
                        return;
                    },
                    'n' => {
                        // gn - enter path input mode
                        self.enterPathInputMode();
                        return;
                    },
                    else => {
                        // Invalid sequence, fall through to normal handling
                    },
                }
            }
        }

        switch (key_char) {
            vaxis.Key.escape => {
                // Clear search if active (check input_buffer for 0-match case)
                if (self.input_buffer.items.len > 0) {
                    self.clearSearch();
                }
            },
            'q' => self.should_quit = true,
            'j', vaxis.Key.down => self.moveCursor(1),
            'k', vaxis.Key.up => self.moveCursor(-1),
            'l', vaxis.Key.right, vaxis.Key.enter => try self.expandOrEnter(),
            'o' => try self.togglePreview(),
            'h', vaxis.Key.left => self.handleBack(),
            '.' => self.toggleHidden(), // Changed from 'a' to '.'
            'g' => self.pending_key.set('g'), // Start multi-key sequence
            'G' => self.jumpToBottom(),
            'H' => self.collapseAll(),
            'L' => self.expandAll(),
            vaxis.Key.tab => try self.toggleCurrentDirectory(),
            '/' => self.enterSearchMode(),
            'n' => self.nextSearchMatch(),
            'N' => self.prevSearchMatch(),
            'R' => try self.reloadTree(),
            'c' => try self.copyPathToClipboard(false),
            'C' => try self.copyPathToClipboard(true),
            '?' => self.enterHelpMode(),
            else => {},
        }
    }

    fn handlePreviewKey(self: *Self, key_char: u21) void {
        switch (key_char) {
            'q' => self.should_quit = true,
            'o', 'h' => self.closePreview(),
            'j' => self.scrollPreviewDown(self.vx.window().height),
            'k' => if (self.preview_scroll > 0) {
                self.preview_scroll -= 1;
            },
            else => {},
        }
    }

    fn handleSearchKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (key_char) {
            vaxis.Key.escape => {
                // Clear search and return to normal mode
                self.clearSearch();
                self.mode = .tree_view;
            },
            vaxis.Key.enter => {
                // Confirm search and return to normal mode
                self.mode = .tree_view;
            },
            vaxis.Key.backspace => {
                // Remove last character
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                    try self.updateSearchResults();
                }
            },
            else => {
                // Add printable character to search buffer
                if (key_char >= 0x20 and key_char < 0x7F) {
                    try self.input_buffer.append(self.allocator, @intCast(key_char));
                    try self.updateSearchResults();
                }
            },
        }
        _ = key;
    }

    fn handlePathInputKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (key_char) {
            vaxis.Key.escape => {
                // Cancel and return to normal mode
                self.input_buffer.clearRetainingCapacity();
                self.mode = .tree_view;
            },
            vaxis.Key.enter => {
                // Validate and navigate to path
                try self.navigateToInputPath();
            },
            vaxis.Key.backspace => {
                // Remove last character
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                // Add printable character to input buffer
                if (key_char >= 0x20 and key_char < 0x7F) {
                    try self.input_buffer.append(self.allocator, @intCast(key_char));
                }
            },
        }
        _ = key;
    }

    fn handleHelpKey(self: *Self) void {
        // Any key dismisses help
        self.mode = .tree_view;
    }

    fn moveCursor(self: *Self, delta: i32) void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const visible_count = ft.countVisible(self.show_hidden);
        if (visible_count == 0) return;

        if (delta > 0) {
            const new_cursor = self.cursor +| @as(usize, @intCast(delta));
            self.cursor = @min(new_cursor, visible_count -| 1);
        } else {
            const abs_delta = @as(usize, @intCast(-delta));
            self.cursor = self.cursor -| abs_delta;
        }

        // Update scroll offset to follow cursor
        self.updateScrollOffset();
    }

    fn updateScrollOffset(self: *Self) void {
        // Get visible tree height (total height minus status bar area)
        const win = self.vx.window();
        const tree_height: usize = if (win.height > 2) win.height - 2 else win.height;
        if (tree_height == 0) return;

        // Scroll up if cursor is above visible area
        if (self.cursor < self.scroll_offset) {
            self.scroll_offset = self.cursor;
        }

        // Scroll down if cursor is below visible area
        // cursor should be at most scroll_offset + tree_height - 1 (last visible row)
        if (self.cursor > self.scroll_offset + tree_height - 1) {
            self.scroll_offset = self.cursor - (tree_height - 1);
        }
    }

    fn toggleHidden(self: *Self) void {
        self.show_hidden = !self.show_hidden;

        // Clamp cursor to new visible count
        if (self.file_tree) |ft| {
            const visible_count = ft.countVisible(self.show_hidden);
            if (visible_count == 0) {
                self.cursor = 0;
            } else if (self.cursor >= visible_count) {
                self.cursor = visible_count - 1;
            }
        }
    }

    /// l/Enter: expand directory, or open preview for files
    fn expandOrEnter(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;

        const entry = &ft.entries.items[actual_index];
        if (entry.kind == .directory) {
            try ft.toggleExpand(actual_index);
        } else {
            try self.openPreview(entry.path);
        }
    }

    /// o: toggle preview (open on file, close if already in preview)
    fn togglePreview(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;

        const entry = &ft.entries.items[actual_index];
        if (entry.kind != .directory) {
            try self.openPreview(entry.path);
        }
        // On directory, o does nothing
    }

    fn handleBack(self: *Self) void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;

        const entry = &ft.entries.items[actual_index];
        if (entry.kind == .directory and entry.expanded) {
            // Collapse expanded directory
            ft.collapseAt(actual_index);
        } else if (entry.depth > 0) {
            // Move to parent directory
            self.moveToParent(actual_index);
        }
    }

    fn moveToParent(self: *Self, current_index: usize) void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const current_entry = ft.entries.items[current_index];
        const target_depth = current_entry.depth - 1;

        // Search backwards for parent directory
        var i = current_index;
        while (i > 0) {
            i -= 1;
            const entry = ft.entries.items[i];
            if (entry.kind == .directory and entry.depth == target_depth) {
                // Found parent, convert to visible index
                if (ft.actualToVisibleIndex(i, self.show_hidden)) |visible_index| {
                    self.cursor = visible_index;
                    self.updateScrollOffset();
                }
                return;
            }
        }
    }

    fn openPreview(self: *Self, path: []const u8) !void {
        // Free previous content
        if (self.preview_content) |content| {
            self.allocator.free(content);
            self.preview_content = null;
        }
        if (self.preview_path) |p| {
            self.allocator.free(p);
            self.preview_path = null;
        }

        // Read file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    self.preview_content = try self.allocator.dupe(u8, "[Access Denied]");
                    self.preview_path = try self.allocator.dupe(u8, path);
                    self.preview_scroll = 0;
                    self.mode = .preview;
                    return;
                },
                else => return err,
            }
        };
        defer file.close();

        const max_size = 100 * 1024; // 100KB max
        const content = file.readToEndAlloc(self.allocator, max_size) catch |err| {
            // Check if file is too large by attempting to get metadata
            const stat = file.stat() catch {
                self.preview_content = try self.allocator.dupe(u8, "[Unable to read file]");
                self.preview_path = try self.allocator.dupe(u8, path);
                self.preview_scroll = 0;
                self.mode = .preview;
                return;
            };
            if (stat.size > max_size) {
                self.preview_content = try self.allocator.dupe(u8, "[File too large]");
                self.preview_path = try self.allocator.dupe(u8, path);
                self.preview_scroll = 0;
                self.mode = .preview;
                return;
            }
            return err;
        };

        // Check for binary content (null bytes indicate binary)
        if (isBinaryContent(content)) {
            self.allocator.free(content);
            const stat = file.stat() catch {
                self.preview_content = try self.allocator.dupe(u8, "[Binary file]");
                self.preview_path = try self.allocator.dupe(u8, path);
                self.preview_scroll = 0;
                self.mode = .preview;
                return;
            };
            var buf: [64]u8 = undefined;
            const size_str = std.fmt.bufPrint(&buf, "[Binary file - {d} bytes]", .{stat.size}) catch "[Binary file]";
            self.preview_content = try self.allocator.dupe(u8, size_str);
            self.preview_path = try self.allocator.dupe(u8, path);
            self.preview_scroll = 0;
            self.mode = .preview;
            return;
        }

        self.preview_content = content;
        self.preview_path = try self.allocator.dupe(u8, path);
        self.preview_scroll = 0;
        self.mode = .preview;
    }

    fn closePreview(self: *Self) void {
        if (self.preview_content) |content| {
            self.allocator.free(content);
            self.preview_content = null;
        }
        if (self.preview_path) |path| {
            self.allocator.free(path);
            self.preview_path = null;
        }
        self.mode = .tree_view;
    }

    /// Scroll preview down by one line, clamping to content bounds
    fn scrollPreviewDown(self: *Self, win_height: u16) void {
        if (self.preview_content) |content| {
            const total_lines = std.mem.count(u8, content, "\n") + 1;
            const visible_rows: usize = if (win_height > 1) win_height - 1 else 1; // Subtract header row
            const max_scroll = if (total_lines > visible_rows) total_lines - visible_rows else 0;
            if (self.preview_scroll < max_scroll) {
                self.preview_scroll += 1;
            }
        }
    }

    // ===== Jump Commands (Task 2.2) =====

    fn jumpToTop(self: *Self) void {
        self.cursor = 0;
        self.scroll_offset = 0;
    }

    fn jumpToBottom(self: *Self) void {
        if (self.file_tree) |ft| {
            const visible_count = ft.countVisible(self.show_hidden);
            if (visible_count > 0) {
                self.cursor = visible_count - 1;
                self.updateScrollOffset();
            }
        }
    }

    // ===== Expand/Collapse All (Task 2.3) =====

    fn collapseAll(self: *Self) void {
        if (self.file_tree) |ft| {
            // Collapse from end to start to avoid index issues
            var i: usize = ft.entries.items.len;
            while (i > 0) {
                i -= 1;
                const entry = &ft.entries.items[i];
                if (entry.kind == .directory and entry.expanded) {
                    ft.collapseAt(i);
                }
            }
            // Reset cursor to bounds
            const visible_count = ft.countVisible(self.show_hidden);
            if (self.cursor >= visible_count and visible_count > 0) {
                self.cursor = visible_count - 1;
            }
        }
    }

    fn expandAll(self: *Self) void {
        if (self.file_tree) |ft| {
            // Only expand currently visible directories (not recursively)
            // Record current count to avoid expanding newly added dirs
            const current_len = ft.entries.items.len;
            var i: usize = 0;
            while (i < current_len) {
                const entry = &ft.entries.items[i];
                if (entry.kind == .directory and !entry.expanded) {
                    ft.toggleExpand(i) catch {
                        // Skip directories we can't access (permission denied, etc.)
                    };
                }
                i += 1;
            }
        }
    }

    fn toggleCurrentDirectory(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
        const entry = &ft.entries.items[actual_index];

        if (entry.kind == .directory) {
            try ft.toggleExpand(actual_index);
        }
    }

    // ===== Search Mode (Task 2.5, 2.6, 2.7, 2.8) =====

    fn enterSearchMode(self: *Self) void {
        self.input_buffer.clearRetainingCapacity();
        self.mode = .search;
    }

    fn clearSearch(self: *Self) void {
        self.input_buffer.clearRetainingCapacity();
        if (self.search_query) |query| {
            self.allocator.free(query);
            self.search_query = null;
        }
        self.search_matches.clearRetainingCapacity();
        self.current_match = 0;
    }

    fn updateSearchResults(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        // Clear previous matches
        self.search_matches.clearRetainingCapacity();

        if (self.input_buffer.items.len == 0) return;

        // Find matching entries (case-insensitive)
        const query = self.input_buffer.items;
        for (ft.entries.items, 0..) |entry, i| {
            if (!self.show_hidden and entry.is_hidden) continue;
            if (containsIgnoreCase(entry.name, query)) {
                try self.search_matches.append(self.allocator, i);
            }
        }

        // Jump to first match
        if (self.search_matches.items.len > 0) {
            self.current_match = 0;
            const actual_index = self.search_matches.items[0];
            // Convert actual index to visible index
            if (ft.actualToVisibleIndex(actual_index, self.show_hidden)) |visible_index| {
                self.cursor = visible_index;
            }
        }
    }

    fn nextSearchMatch(self: *Self) void {
        if (self.search_matches.items.len == 0) return;
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        self.current_match = (self.current_match + 1) % self.search_matches.items.len;
        const actual_index = self.search_matches.items[self.current_match];
        if (ft.actualToVisibleIndex(actual_index, self.show_hidden)) |visible_index| {
            self.cursor = visible_index;
        }
    }

    fn prevSearchMatch(self: *Self) void {
        if (self.search_matches.items.len == 0) return;
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        if (self.current_match == 0) {
            self.current_match = self.search_matches.items.len - 1;
        } else {
            self.current_match -= 1;
        }
        const actual_index = self.search_matches.items[self.current_match];
        if (ft.actualToVisibleIndex(actual_index, self.show_hidden)) |visible_index| {
            self.cursor = visible_index;
        }
    }

    // ===== Path Navigation (Task 2.4) =====

    fn enterPathInputMode(self: *Self) void {
        self.input_buffer.clearRetainingCapacity();
        self.mode = .path_input;
    }

    fn navigateToInputPath(self: *Self) !void {
        if (self.input_buffer.items.len == 0) {
            self.mode = .tree_view;
            return;
        }

        // Expand ~ to home directory
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const input_path = self.input_buffer.items;
        var resolved_path: []const u8 = undefined;

        if (input_path.len > 0 and input_path[0] == '~') {
            const home = std.posix.getenv("HOME") orelse {
                self.status_message = "Cannot resolve home directory";
                return;
            };
            if (input_path.len == 1) {
                resolved_path = home;
            } else {
                const written = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ home, input_path[1..] }) catch {
                    self.status_message = "Path too long";
                    return;
                };
                resolved_path = written;
            }
        } else {
            resolved_path = input_path;
        }

        // Check if path exists
        const stat = std.fs.cwd().statFile(resolved_path) catch {
            self.status_message = "Invalid path";
            return;
        };

        // Determine target directory
        var target_dir: []const u8 = undefined;
        if (stat.kind == .directory) {
            target_dir = resolved_path;
        } else {
            // File path - get parent directory
            target_dir = std.fs.path.dirname(resolved_path) orelse ".";
        }

        // Reload tree at new path
        if (self.file_tree) |ft| {
            ft.deinit();
        }
        self.file_tree = try tree.FileTree.init(self.allocator, target_dir);
        try self.file_tree.?.readDirectory();

        self.cursor = 0;
        self.scroll_offset = 0;
        self.input_buffer.clearRetainingCapacity();
        self.mode = .tree_view;
    }

    // ===== Reload Tree (Task 2.10) =====

    fn reloadTree(self: *Self) !void {
        if (self.file_tree) |ft| {
            const root_path = try self.allocator.dupe(u8, ft.root_path);
            defer self.allocator.free(root_path);

            ft.deinit();
            self.file_tree = try tree.FileTree.init(self.allocator, root_path);
            try self.file_tree.?.readDirectory();

            // Clamp cursor
            const visible_count = self.file_tree.?.countVisible(self.show_hidden);
            if (self.cursor >= visible_count and visible_count > 0) {
                self.cursor = visible_count - 1;
            }
            self.status_message = "Reloaded";
        }
    }

    // ===== Clipboard Operations (Task 2.11) =====

    fn copyPathToClipboard(self: *Self, filename_only: bool) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
        const entry = &ft.entries.items[actual_index];

        const text = if (filename_only) entry.name else entry.path;

        // Use OSC 52 to copy to clipboard
        const writer = self.tty.writer();
        const encoded = try encodeBase64(self.render_arena.allocator(), text);

        // OSC 52: \x1b]52;c;<base64>\x07
        try writer.print("\x1b]52;c;{s}\x07", .{encoded});
        try writer.flush();

        // Set status message
        if (filename_only) {
            self.status_message = "Copied filename";
        } else {
            self.status_message = "Copied path";
        }
    }

    // ===== Help Mode (Task 2.12) =====

    fn enterHelpMode(self: *Self) void {
        self.mode = .help;
    }

    fn render(self: *Self, writer: anytype) !void {
        // Reset render arena - frees all allocations from previous render
        _ = self.render_arena.reset(.retain_capacity);

        const win = self.vx.window();
        win.clear();

        const height = win.height;

        const arena = self.render_arena.allocator();

        switch (self.mode) {
            .tree_view, .search, .path_input => {
                // Main tree view (leave room for status bar if height > 2)
                const tree_height: u16 = if (height > 2) height - 2 else height;
                var tree_win = win.child(.{ .height = tree_height });
                tree_win.clear();
                if (self.file_tree) |ft| {
                    // Pass search query for highlighting if search is active
                    const search_query: ?[]const u8 = if (self.input_buffer.items.len > 0)
                        self.input_buffer.items
                    else
                        null;
                    try ui.renderTree(tree_win, ft, self.cursor, self.scroll_offset, self.show_hidden, search_query, self.search_matches.items, arena);
                } else {
                    _ = tree_win.printSegment(.{ .text = "No directory loaded" }, .{});
                }

                // Status bar at bottom (only if we have room)
                if (height > 2) {
                    try self.renderStatusBar(win, tree_height, arena);
                }
            },
            .preview => {
                if (self.preview_content) |content| {
                    const filename = if (self.preview_path) |p| std.fs.path.basename(p) else "preview";
                    try ui.renderPreview(win, content, filename, self.preview_scroll, self.render_arena.allocator());
                }
            },
            .help => {
                try ui.renderHelp(win);
            },
        }

        try self.vx.render(writer);
    }

    fn renderStatusBar(self: *Self, win: vaxis.Window, row: u16, arena: std.mem.Allocator) !void {
        // Row 1: Path and status
        try self.renderStatusRow1(win, arena, row);

        // Row 2: Keybinding hints
        if (row + 1 < win.height) {
            try self.renderStatusRow2(win, row + 1);
        }
    }

    fn renderStatusRow1(self: *Self, win: vaxis.Window, arena: std.mem.Allocator, row: u16) !void {
        switch (self.mode) {
            .search => {
                // Search mode: "/query" [N matches]
                const match_count = self.search_matches.items.len;
                const safe_query = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                const status = try std.fmt.allocPrint(arena, "/{s}|  [{d} matches]", .{ safe_query, match_count });
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .reverse = true },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .path_input => {
                // Path input mode: "Go to: path"
                const safe_path = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                const status = try std.fmt.allocPrint(arena, "Go to: {s}|", .{safe_path});
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .reverse = true },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .tree_view => {
                // Show current directory path (sanitized)
                if (self.file_tree) |ft| {
                    const safe_root = try ui.sanitizeForDisplay(arena, ft.root_path);
                    const max_path_width: usize = @as(usize, win.width) -| 20; // Leave room for status
                    if (max_path_width <= 3) {
                        // Window too narrow, skip path display
                    } else if (safe_root.len > max_path_width) {
                        // Show "..." prefix for long paths
                        _ = win.printSegment(.{
                            .text = "...",
                            .style = .{ .fg = .{ .index = 8 } }, // dim
                        }, .{ .row_offset = row, .col_offset = 0 });
                        const suffix_start = safe_root.len - (max_path_width - 3);
                        _ = win.printSegment(.{
                            .text = safe_root[suffix_start..],
                            .style = .{ .fg = .{ .index = 6 }, .bold = true }, // cyan, bold
                        }, .{ .row_offset = row, .col_offset = 3 });
                    } else {
                        _ = win.printSegment(.{
                            .text = safe_root,
                            .style = .{ .fg = .{ .index = 6 }, .bold = true }, // cyan, bold
                        }, .{ .row_offset = row, .col_offset = 0 });
                    }
                }

                // Show pending key, search status, or status message on the right
                if (self.pending_key.get()) |pending| {
                    const pending_str = try std.fmt.allocPrint(arena, "{c}-", .{@as(u8, @intCast(pending))});
                    const col: u16 = @intCast(win.width -| pending_str.len -| 1);
                    _ = win.printSegment(.{
                        .text = pending_str,
                        .style = .{ .fg = .{ .index = 3 } }, // yellow
                    }, .{ .row_offset = row, .col_offset = col });
                } else if (self.input_buffer.items.len > 0) {
                    // Show active search query and match count
                    const safe_query = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                    const match_count = self.search_matches.items.len;
                    const current = if (match_count > 0) self.current_match + 1 else 0;
                    const search_status = try std.fmt.allocPrint(arena, "/{s} [{d}/{d}]", .{
                        safe_query,
                        current,
                        match_count,
                    });
                    const col: u16 = @intCast(win.width -| search_status.len -| 1);
                    // Red for no matches, yellow for matches
                    const style: vaxis.Style = if (match_count == 0)
                        .{ .fg = .{ .index = 1 }, .bold = true } // red
                    else
                        .{ .fg = .{ .index = 3 }, .bold = true }; // yellow
                    _ = win.printSegment(.{
                        .text = search_status,
                        .style = style,
                    }, .{ .row_offset = row, .col_offset = col });
                } else if (self.status_message) |msg| {
                    const safe_msg = try ui.sanitizeForDisplay(arena, msg);
                    const col: u16 = @intCast(win.width -| safe_msg.len -| 1);
                    _ = win.printSegment(.{
                        .text = safe_msg,
                        .style = .{ .fg = .{ .index = 2 } }, // green
                    }, .{ .row_offset = row, .col_offset = col });
                }
            },
            else => {},
        }
    }

    fn renderStatusRow2(self: *Self, win: vaxis.Window, row: u16) !void {
        const hints: []const u8 = switch (self.mode) {
            .tree_view => if (self.input_buffer.items.len > 0)
                "n/N:next/prev  Esc:clear search  /:new search  ?:help  q:quit"
            else
                "j/k:move  h/l:collapse/expand  o:preview  .:hidden  /:search  ?:help  q:quit",
            .search => "Enter:confirm  Esc:cancel",
            .path_input => "Enter:go  Esc:cancel",
            .preview => "j/k:scroll  o:close  q:quit",
            else => "",
        };

        if (hints.len > 0) {
            _ = win.printSegment(.{
                .text = hints,
                .style = .{ .fg = .{ .index = 8 } }, // dim
            }, .{ .row_offset = row, .col_offset = 0 });
        }
    }
};

/// Case-insensitive substring search (delegates to ui.findMatchPosition)
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    return ui.findMatchPosition(haystack, needle) != null;
}

/// Base64 encode for OSC 52 clipboard
fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const pad = '=';

    const out_len = ((data.len + 2) / 3) * 4;
    var result = try allocator.alloc(u8, out_len);

    var i: usize = 0;
    var j: usize = 0;
    while (i < data.len) {
        const b0 = data[i];
        const b1 = if (i + 1 < data.len) data[i + 1] else 0;
        const b2 = if (i + 2 < data.len) data[i + 2] else 0;

        result[j] = alphabet[b0 >> 2];
        result[j + 1] = alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        result[j + 2] = if (i + 1 < data.len) alphabet[((b1 & 0x0F) << 2) | (b2 >> 6)] else pad;
        result[j + 3] = if (i + 2 < data.len) alphabet[b2 & 0x3F] else pad;

        i += 3;
        j += 4;
    }

    return result;
}

/// Check if content contains null bytes (indicates binary file)
fn isBinaryContent(content: []const u8) bool {
    // Check first 8KB for null bytes
    const check_len = @min(content.len, 8192);
    for (content[0..check_len]) |byte| {
        if (byte == 0) return true;
    }
    return false;
}

pub fn run(allocator: std.mem.Allocator, start_path: []const u8) !void {
    const app = try App.init(allocator);
    defer app.deinit();

    // Load directory
    app.file_tree = try tree.FileTree.init(allocator, start_path);
    try app.file_tree.?.readDirectory();

    // Run event loop
    try app.runEventLoop();
}

test "App state transitions" {
    // Test mode enum values
    var mode: AppMode = .tree_view;
    try std.testing.expectEqual(AppMode.tree_view, mode);

    mode = .preview;
    try std.testing.expectEqual(AppMode.preview, mode);
}

test "isBinaryContent detects null bytes" {
    // Text content should not be detected as binary
    const text = "Hello, world!\nThis is text.";
    try std.testing.expect(!isBinaryContent(text));

    // Content with null byte should be detected as binary
    const binary = "Hello\x00World";
    try std.testing.expect(isBinaryContent(binary));

    // Empty content is not binary
    try std.testing.expect(!isBinaryContent(""));
}

test "containsIgnoreCase" {
    // Basic case-insensitive matching
    try std.testing.expect(containsIgnoreCase("HelloWorld", "world"));
    try std.testing.expect(containsIgnoreCase("HelloWorld", "HELLO"));
    try std.testing.expect(containsIgnoreCase("test.txt", "TEST"));
    try std.testing.expect(!containsIgnoreCase("hello", "xyz"));

    // Edge cases
    try std.testing.expect(containsIgnoreCase("a", ""));
    try std.testing.expect(!containsIgnoreCase("", "a"));
}
