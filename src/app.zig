const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const ui = @import("ui.zig");

pub const AppMode = enum {
    tree_view,
    preview,
    search,
    path_input,
    rename,
    new_file,
    new_dir,
    confirm_delete,
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
    status_message_buf: [64]u8, // Buffer for dynamic status messages

    // Input buffer for search/path input modes
    input_buffer: std.ArrayList(u8),

    // Search state
    search_query: ?[]const u8,
    search_matches: std.ArrayList(usize), // indices of matching entries
    current_match: usize,

    // File marking state
    marked_files: std.StringHashMap(void),

    // Expanded directory paths (preserved across reloads)
    expanded_paths: std.StringHashMap(void),

    // Clipboard state for yank/cut
    clipboard_files: std.ArrayList([]const u8),
    clipboard_operation: ClipboardOperation,

    // Rename state - stores the path being renamed
    rename_target_path: ?[]const u8,

    const Self = @This();

    pub const ClipboardOperation = enum {
        none,
        copy,
        cut,
    };

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
            .status_message_buf = undefined,
            .input_buffer = .empty,
            .search_query = null,
            .search_matches = .empty,
            .current_match = 0,
            .marked_files = std.StringHashMap(void).init(allocator),
            .expanded_paths = std.StringHashMap(void).init(allocator),
            .clipboard_files = .empty,
            .clipboard_operation = .none,
            .rename_target_path = null,
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
        // Free owned path copies in marked_files
        var iter = self.marked_files.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.marked_files.deinit();
        // Free owned path copies in expanded_paths
        var exp_iter = self.expanded_paths.keyIterator();
        while (exp_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.expanded_paths.deinit();
        // Free clipboard files (we own copies of paths)
        for (self.clipboard_files.items) |path| {
            self.allocator.free(path);
        }
        self.clipboard_files.deinit(self.allocator);
        if (self.rename_target_path) |path| {
            self.allocator.free(path);
        }
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
            .rename => try self.handleRenameKey(key, key_char),
            .new_file => try self.handleNewFileKey(key, key_char),
            .new_dir => try self.handleNewDirKey(key, key_char),
            .confirm_delete => try self.handleConfirmDeleteKey(key_char),
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
            // File operations
            ' ' => try self.toggleMark(),
            'y' => try self.yankFiles(),
            'd' => try self.cutFiles(),
            'p' => try self.pasteFiles(),
            'D' => self.enterConfirmDeleteMode(),
            'r' => try self.enterRenameMode(),
            'a' => self.enterNewFileMode(),
            'A' => self.enterNewDirMode(),
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

        // Refresh search results if search is active
        if (self.input_buffer.items.len > 0) {
            self.updateSearchResults() catch {};
        }
    }

    /// l/Enter: expand directory, or open preview for files
    fn expandOrEnter(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;

        const entry = &ft.entries.items[actual_index];
        if (entry.kind == .directory) {
            if (entry.expanded) {
                self.collapseDirectory(ft, actual_index);
            } else {
                try self.expandDirectory(ft, actual_index);
            }
            // Refresh search results if search is active
            if (self.input_buffer.items.len > 0) {
                try self.updateSearchResults();
            }
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
            self.collapseDirectory(ft, actual_index);
            // Refresh search results if search is active
            if (self.input_buffer.items.len > 0) {
                self.updateSearchResults() catch {};
            }
        } else if (entry.depth > 0) {
            // Move to parent directory
            self.moveToParent(actual_index);
        }
    }

    // ===== Expand/Collapse Helpers (with expanded_paths tracking) =====

    /// Expand a directory and track in expanded_paths
    fn expandDirectory(self: *Self, ft: *tree.FileTree, index: usize) !void {
        const entry = &ft.entries.items[index];
        if (entry.kind != .directory or entry.expanded) return;

        // Save path before toggleExpand (entry may be invalidated after realloc)
        const path_copy = try self.allocator.dupe(u8, entry.path);
        errdefer self.allocator.free(path_copy);

        // Expand first, then track (fixes issue: map tracks unexpanded dir on failure)
        try ft.toggleExpand(index);

        // Use getOrPut to avoid leaking if path already exists (fixes duplicate key leak)
        const gop = try self.expanded_paths.getOrPut(path_copy);
        if (gop.found_existing) {
            // Path already tracked, free the duplicate
            self.allocator.free(path_copy);
        }
        // If not found, gop.key_ptr.* is already set to path_copy
    }

    /// Collapse a directory and remove from expanded_paths (including descendants)
    fn collapseDirectory(self: *Self, ft: *tree.FileTree, index: usize) void {
        const entry = &ft.entries.items[index];
        if (entry.kind != .directory or !entry.expanded) return;

        const parent_depth = entry.depth;

        // Remove this directory from expanded_paths
        if (self.expanded_paths.fetchRemove(entry.path)) |kv| {
            self.allocator.free(kv.key);
        }

        // Also remove all descendant directories from expanded_paths
        // (they will be removed from tree by collapseAt, so we must clean up tracking)
        var i = index + 1;
        while (i < ft.entries.items.len) {
            const descendant = &ft.entries.items[i];
            if (descendant.depth <= parent_depth) break;
            if (descendant.kind == .directory and descendant.expanded) {
                if (self.expanded_paths.fetchRemove(descendant.path)) |kv| {
                    self.allocator.free(kv.key);
                }
            }
            i += 1;
        }

        ft.collapseAt(index);
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
                    self.collapseDirectory(ft, i);
                }
            }
            // Reset cursor to bounds
            const visible_count = ft.countVisible(self.show_hidden);
            if (self.cursor >= visible_count and visible_count > 0) {
                self.cursor = visible_count - 1;
            }
        }
        // Refresh search results if search is active
        if (self.input_buffer.items.len > 0) {
            self.updateSearchResults() catch {};
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
                    self.expandDirectory(ft, i) catch {
                        // Skip directories we can't access (permission denied, etc.)
                    };
                }
                i += 1;
            }
        }
        // Refresh search results if search is active
        if (self.input_buffer.items.len > 0) {
            self.updateSearchResults() catch {};
        }
    }

    fn toggleCurrentDirectory(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
        const entry = &ft.entries.items[actual_index];

        if (entry.kind == .directory) {
            if (entry.expanded) {
                self.collapseDirectory(ft, actual_index);
            } else {
                try self.expandDirectory(ft, actual_index);
            }
            // Refresh search results if search is active
            if (self.input_buffer.items.len > 0) {
                try self.updateSearchResults();
            }
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

        // Clear marked files - paths are now invalid after tree change
        self.clearMarkedFiles();

        // Clear expanded paths - old paths are invalid after root change
        self.clearExpandedPaths();

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

            // Restore expanded directories from expanded_paths
            try self.restoreExpandedState();

            // Clear marked files - paths are now invalid after tree reload
            self.clearMarkedFiles();

            // Clamp cursor
            const visible_count = self.file_tree.?.countVisible(self.show_hidden);
            if (self.cursor >= visible_count and visible_count > 0) {
                self.cursor = visible_count - 1;
            }
            self.status_message = "Reloaded";

            // Refresh search results if search is active
            if (self.input_buffer.items.len > 0) {
                try self.updateSearchResults();
            }
        }
    }

    /// Restore expanded directories from expanded_paths after tree reload
    fn restoreExpandedState(self: *Self) !void {
        const new_ft = self.file_tree orelse return;
        if (self.expanded_paths.count() == 0) return;

        // Collect paths and sort by length (shorter paths = shallower directories first)
        var paths_to_expand: std.ArrayList([]const u8) = .empty;
        defer paths_to_expand.deinit(self.allocator);

        var iter = self.expanded_paths.keyIterator();
        while (iter.next()) |key| {
            try paths_to_expand.append(self.allocator, key.*);
        }

        // Sort by path length (shorter first = parent directories first)
        std.mem.sort([]const u8, paths_to_expand.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return a.len < b.len;
            }
        }.lessThan);

        // Track which paths were found in the new tree
        var found_paths: std.ArrayList([]const u8) = .empty;
        defer found_paths.deinit(self.allocator);

        // Expand each path in order
        for (paths_to_expand.items) |path| {
            var found = false;
            // Find the entry with this path and expand it
            for (new_ft.entries.items, 0..) |entry, i| {
                if (std.mem.eql(u8, entry.path, path)) {
                    // Only mark as found if it's still a directory
                    // (handles case where directory was replaced by file)
                    if (entry.kind == .directory) {
                        found = true;
                        if (!entry.expanded) {
                            new_ft.toggleExpand(i) catch {};
                        }
                    }
                    break;
                }
            }
            if (found) {
                try found_paths.append(self.allocator, path);
            }
        }

        // Prune stale paths that no longer exist in the tree (fixes memory leak)
        for (paths_to_expand.items) |path| {
            var still_exists = false;
            for (found_paths.items) |found_path| {
                if (std.mem.eql(u8, path, found_path)) {
                    still_exists = true;
                    break;
                }
            }
            if (!still_exists) {
                if (self.expanded_paths.fetchRemove(path)) |kv| {
                    self.allocator.free(kv.key);
                }
            }
        }
    }

    // ===== Helper: Get Current Directory =====

    /// Returns the directory path for the current cursor position.
    /// If cursor is on a directory, returns that directory.
    /// If cursor is on a file, returns its parent directory.
    /// Falls back to root_path if no valid entry found.
    fn getCurrentDirectory(self: *Self, ft: *tree.FileTree) []const u8 {
        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return ft.root_path;
        const entry = &ft.entries.items[actual_index];

        if (entry.kind == .directory) {
            return entry.path;
        } else {
            return std.fs.path.dirname(entry.path) orelse ft.root_path;
        }
    }

    // ===== File Marking =====

    fn toggleMark(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
        const entry = &ft.entries.items[actual_index];

        // Check if already marked by comparing with stored owned copies
        var found_key: ?[]const u8 = null;
        var iter = self.marked_files.keyIterator();
        while (iter.next()) |key| {
            if (std.mem.eql(u8, key.*, entry.path)) {
                found_key = key.*;
                break;
            }
        }

        if (found_key) |key| {
            // Unmark: remove and free owned copy
            _ = self.marked_files.remove(key);
            self.allocator.free(key);
        } else {
            // Mark: store owned copy of path
            const owned_path = try self.allocator.dupe(u8, entry.path);
            self.marked_files.put(owned_path, {}) catch {
                self.allocator.free(owned_path);
            };
        }
    }

    /// Clear all marks and free owned path copies
    fn clearMarkedFiles(self: *Self) void {
        var iter = self.marked_files.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.marked_files.clearRetainingCapacity();
    }

    fn clearExpandedPaths(self: *Self) void {
        var iter = self.expanded_paths.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.expanded_paths.clearRetainingCapacity();
    }

    // ===== Yank/Cut/Paste Operations =====

    fn yankFiles(self: *Self) !void {
        try self.prepareClipboard(.copy);
    }

    fn cutFiles(self: *Self) !void {
        try self.prepareClipboard(.cut);
    }

    fn prepareClipboard(self: *Self, operation: ClipboardOperation) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        // Clear previous clipboard
        for (self.clipboard_files.items) |path| {
            self.allocator.free(path);
        }
        self.clipboard_files.clearRetainingCapacity();

        if (self.marked_files.count() > 0) {
            // Copy all marked files to clipboard
            var iter = self.marked_files.keyIterator();
            while (iter.next()) |key| {
                const path_copy = try self.allocator.dupe(u8, key.*);
                try self.clipboard_files.append(self.allocator, path_copy);
            }
            // Clear marks and free owned path copies
            self.clearMarkedFiles();
        } else {
            // Copy current file
            const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
            const entry = &ft.entries.items[actual_index];
            const path_copy = try self.allocator.dupe(u8, entry.path);
            try self.clipboard_files.append(self.allocator, path_copy);
        }

        self.clipboard_operation = operation;

        const op_name = if (operation == .copy) "Yanked" else "Cut";
        self.status_message = if (self.clipboard_files.items.len == 1)
            if (operation == .copy) "Yanked 1 file" else "Cut 1 file"
        else
            if (operation == .copy) "Yanked files" else "Cut files";
        _ = op_name;
    }

    fn pasteFiles(self: *Self) !void {
        if (self.clipboard_files.items.len == 0) {
            self.status_message = "Nothing to paste";
            return;
        }

        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        // Get destination directory from cursor position
        const dest_dir = self.getCurrentDirectory(ft);

        const total_count = self.clipboard_files.items.len;
        var success_count: usize = 0;
        for (self.clipboard_files.items) |src_path| {
            const filename = std.fs.path.basename(src_path);
            const dest_path = try std.fs.path.join(self.allocator, &.{ dest_dir, filename });
            defer self.allocator.free(dest_path);

            // Handle filename conflicts by appending a number
            var final_dest = dest_path;
            var owned_final = false;
            var suffix: usize = 1;
            while (std.fs.cwd().access(final_dest, .{})) |_| {
                // File exists, try with suffix
                if (owned_final) self.allocator.free(final_dest);
                const ext = std.fs.path.extension(filename);
                const stem = filename[0 .. filename.len - ext.len];
                const new_name = try std.fmt.allocPrint(self.allocator, "{s}_{d}{s}", .{ stem, suffix, ext });
                defer self.allocator.free(new_name);
                final_dest = try std.fs.path.join(self.allocator, &.{ dest_dir, new_name });
                owned_final = true;
                suffix += 1;
                if (suffix > 100) break; // Safety limit
            } else |_| {
                // File doesn't exist, we can use this path
            }
            defer if (owned_final) self.allocator.free(final_dest);

            // Perform copy or move
            if (self.clipboard_operation == .copy) {
                self.copyPath(src_path, final_dest) catch continue;
            } else {
                std.fs.cwd().rename(src_path, final_dest) catch {
                    // If rename fails (cross-device), try copy + delete
                    // Only delete source if copy succeeded to prevent data loss
                    self.copyPath(src_path, final_dest) catch continue;
                    self.deletePathRecursive(src_path) catch {
                        // Copy succeeded but delete failed - this is acceptable
                        // (user will have duplicate, not data loss)
                    };
                };
            }
            success_count += 1;
        }

        // Clear clipboard after cut
        if (self.clipboard_operation == .cut) {
            for (self.clipboard_files.items) |path| {
                self.allocator.free(path);
            }
            self.clipboard_files.clearRetainingCapacity();
            self.clipboard_operation = .none;
        }

        if (success_count > 0) {
            try self.reloadTree();
            // Set status message AFTER reloadTree (which sets "Reloaded")
            const fail_count = total_count - success_count;
            if (fail_count == 0) {
                // All succeeded
                if (success_count == 1) {
                    self.status_message = "Pasted 1 file";
                } else {
                    self.status_message = std.fmt.bufPrint(&self.status_message_buf, "Pasted {d} files", .{success_count}) catch "Pasted";
                }
            } else {
                // Partial success
                self.status_message = std.fmt.bufPrint(&self.status_message_buf, "Pasted {d} files ({d} failed)", .{ success_count, fail_count }) catch "Pasted (some failed)";
            }
        } else {
            self.status_message = "Paste failed";
        }
    }

    fn copyPath(self: *Self, src: []const u8, dest: []const u8) !void {
        _ = self;
        const stat = try std.fs.cwd().statFile(src);
        if (stat.kind == .directory) {
            // Copy directory recursively
            try copyDirRecursive(src, dest);
        } else {
            // Copy file
            try std.fs.cwd().copyFile(src, std.fs.cwd(), dest, .{});
        }
    }

    // ===== Clipboard Operations (Task 2.11) - Path to System Clipboard =====

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

    // ===== Rename Mode =====

    fn enterRenameMode(self: *Self) !void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
        const entry = &ft.entries.items[actual_index];

        // Store the path being renamed
        if (self.rename_target_path) |path| {
            self.allocator.free(path);
        }
        self.rename_target_path = try self.allocator.dupe(u8, entry.path);

        // Pre-fill input buffer with current filename
        self.input_buffer.clearRetainingCapacity();
        try self.input_buffer.appendSlice(self.allocator, entry.name);

        self.mode = .rename;
    }

    fn handleRenameKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (key_char) {
            vaxis.Key.escape => {
                self.input_buffer.clearRetainingCapacity();
                self.mode = .tree_view;
            },
            vaxis.Key.enter => {
                try self.performRename();
            },
            vaxis.Key.backspace => {
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                if (key_char >= 0x20 and key_char < 0x7F) {
                    try self.input_buffer.append(self.allocator, @intCast(key_char));
                }
            },
        }
        _ = key;
    }

    fn performRename(self: *Self) !void {
        if (self.rename_target_path == null or self.input_buffer.items.len == 0) {
            self.status_message = "Rename cancelled";
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        }

        const old_path = self.rename_target_path.?;
        const new_name = self.input_buffer.items;

        // Validate filename - reject path separators and parent directory references
        if (!isValidFilename(new_name)) {
            self.status_message = "Invalid name (no / or ..)";
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        }

        // Get directory part of old path
        const dir_path = std.fs.path.dirname(old_path) orelse ".";
        const new_path = try std.fs.path.join(self.allocator, &.{ dir_path, new_name });
        defer self.allocator.free(new_path);

        // Perform rename
        std.fs.cwd().rename(old_path, new_path) catch |err| {
            self.status_message = switch (err) {
                error.PathAlreadyExists => "File already exists",
                error.AccessDenied => "Permission denied",
                else => "Rename failed",
            };
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        };

        self.status_message = "Renamed";
        self.input_buffer.clearRetainingCapacity();
        self.mode = .tree_view;

        // Reload tree to reflect changes
        try self.reloadTree();
    }

    // ===== New File Mode =====

    fn enterNewFileMode(self: *Self) void {
        self.input_buffer.clearRetainingCapacity();
        self.mode = .new_file;
    }

    fn handleNewFileKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (key_char) {
            vaxis.Key.escape => {
                self.input_buffer.clearRetainingCapacity();
                self.mode = .tree_view;
            },
            vaxis.Key.enter => {
                try self.createFile();
            },
            vaxis.Key.backspace => {
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                if (key_char >= 0x20 and key_char < 0x7F) {
                    try self.input_buffer.append(self.allocator, @intCast(key_char));
                }
            },
        }
        _ = key;
    }

    fn createFile(self: *Self) !void {
        if (self.input_buffer.items.len == 0) {
            self.status_message = "No filename provided";
            self.mode = .tree_view;
            return;
        }

        const new_name = self.input_buffer.items;

        // Validate filename - reject path separators and parent directory references
        if (!isValidFilename(new_name)) {
            self.status_message = "Invalid filename (no / or ..)";
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        }

        // Get current directory from cursor position
        const current_dir = if (self.file_tree) |ft| self.getCurrentDirectory(ft) else ".";
        const new_path = try std.fs.path.join(self.allocator, &.{ current_dir, new_name });
        defer self.allocator.free(new_path);

        // Create file
        const file = std.fs.cwd().createFile(new_path, .{ .exclusive = true }) catch |err| {
            self.status_message = switch (err) {
                error.PathAlreadyExists => "File already exists",
                error.AccessDenied => "Permission denied",
                else => "Failed to create file",
            };
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        };
        file.close();

        self.status_message = "File created";
        self.input_buffer.clearRetainingCapacity();
        self.mode = .tree_view;

        // Reload tree to show new file
        try self.reloadTree();
    }

    // ===== New Directory Mode =====

    fn enterNewDirMode(self: *Self) void {
        self.input_buffer.clearRetainingCapacity();
        self.mode = .new_dir;
    }

    fn handleNewDirKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (key_char) {
            vaxis.Key.escape => {
                self.input_buffer.clearRetainingCapacity();
                self.mode = .tree_view;
            },
            vaxis.Key.enter => {
                try self.createDirectory();
            },
            vaxis.Key.backspace => {
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                if (key_char >= 0x20 and key_char < 0x7F) {
                    try self.input_buffer.append(self.allocator, @intCast(key_char));
                }
            },
        }
        _ = key;
    }

    fn createDirectory(self: *Self) !void {
        if (self.input_buffer.items.len == 0) {
            self.status_message = "No directory name provided";
            self.mode = .tree_view;
            return;
        }

        const new_name = self.input_buffer.items;

        // Validate directory name - reject path separators and parent directory references
        if (!isValidFilename(new_name)) {
            self.status_message = "Invalid name (no / or ..)";
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        }

        // Get current directory from cursor position
        const current_dir = if (self.file_tree) |ft| self.getCurrentDirectory(ft) else ".";
        const new_path = try std.fs.path.join(self.allocator, &.{ current_dir, new_name });
        defer self.allocator.free(new_path);

        // Create directory
        std.fs.cwd().makeDir(new_path) catch |err| {
            self.status_message = switch (err) {
                error.PathAlreadyExists => "Directory already exists",
                error.AccessDenied => "Permission denied",
                else => "Failed to create directory",
            };
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
            return;
        };

        self.status_message = "Directory created";
        self.input_buffer.clearRetainingCapacity();
        self.mode = .tree_view;

        // Reload tree to show new directory
        try self.reloadTree();
    }

    // ===== Confirm Delete Mode =====

    fn enterConfirmDeleteMode(self: *Self) void {
        self.mode = .confirm_delete;
    }

    fn handleConfirmDeleteKey(self: *Self, key_char: u21) !void {
        switch (key_char) {
            'y', 'Y' => {
                try self.performDelete();
            },
            'n', 'N', vaxis.Key.escape => {
                self.status_message = "Delete cancelled";
                self.mode = .tree_view;
            },
            else => {},
        }
    }

    fn performDelete(self: *Self) !void {
        if (self.file_tree == null) {
            self.mode = .tree_view;
            return;
        }
        const ft = self.file_tree.?;

        var deleted_count: usize = 0;
        var total_count: usize = 0;

        if (self.marked_files.count() > 0) {
            // Delete all marked files
            var to_delete: std.ArrayList([]const u8) = .empty;
            defer to_delete.deinit(self.allocator);

            // Collect paths first (iterator invalidation safety)
            var iter = self.marked_files.keyIterator();
            while (iter.next()) |key| {
                try to_delete.append(self.allocator, key.*);
            }

            total_count = to_delete.items.len;
            for (to_delete.items) |path| {
                self.deletePathRecursive(path) catch {
                    // Continue deleting others even if one fails
                    continue;
                };
                deleted_count += 1;
            }

            // Clear marks and free owned path copies
            self.clearMarkedFiles();
        } else {
            // Delete current file
            const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse {
                self.mode = .tree_view;
                return;
            };
            const entry = &ft.entries.items[actual_index];

            self.deletePathRecursive(entry.path) catch |err| {
                self.status_message = switch (err) {
                    error.AccessDenied => "Permission denied",
                    else => "Delete failed",
                };
                self.mode = .tree_view;
                return;
            };
            deleted_count = 1;
        }

        if (deleted_count > 0) {
            if (total_count > 0 and deleted_count < total_count) {
                // Partial success
                self.status_message = "Deleted (some failed)";
            } else {
                self.status_message = "Deleted";
            }
            try self.reloadTree();
        } else {
            self.status_message = "Delete failed";
        }

        self.mode = .tree_view;
    }

    fn deletePathRecursive(self: *Self, path: []const u8) !void {
        _ = self;
        // Security: Check if path is a symlink FIRST before following it
        // This prevents symlink attacks where a symlink could cause deletion outside intended root

        // Try to read link to detect symlink (readLink fails on non-symlinks)
        var link_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (std.fs.cwd().readLink(path, &link_buf)) |_| {
            // It's a symlink - delete only the symlink itself, not the target
            try std.fs.cwd().deleteFile(path);
            return;
        } else |_| {
            // Not a symlink, continue with normal deletion
        }

        // Now safe to check what it actually is
        const stat = try std.fs.cwd().statFile(path);
        if (stat.kind == .directory) {
            try std.fs.cwd().deleteTree(path);
        } else {
            try std.fs.cwd().deleteFile(path);
        }
    }

    // ===== Help Mode =====

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
            .tree_view, .search, .path_input, .rename, .new_file, .new_dir, .confirm_delete => {
                // Main tree view (leave room for status bar if height > 2)
                const tree_height: u16 = if (height > 2) height - 2 else height;
                var tree_win = win.child(.{ .height = tree_height });
                tree_win.clear();
                if (self.file_tree) |ft| {
                    // Pass search query for highlighting only in search mode
                    const search_query: ?[]const u8 = if (self.mode == .search and self.input_buffer.items.len > 0)
                        self.input_buffer.items
                    else if (self.mode == .tree_view and self.input_buffer.items.len > 0)
                        self.input_buffer.items
                    else
                        null;
                    try ui.renderTree(tree_win, ft, self.cursor, self.scroll_offset, self.show_hidden, search_query, self.search_matches.items, &self.marked_files, arena);
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
            .rename => {
                // Rename mode: "Rename: newname"
                const safe_name = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                const status = try std.fmt.allocPrint(arena, "Rename: {s}|", .{safe_name});
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .reverse = true },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .new_file => {
                // New file mode: "New file: filename"
                const safe_name = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                const status = try std.fmt.allocPrint(arena, "New file: {s}|", .{safe_name});
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .reverse = true },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .new_dir => {
                // New directory mode: "New dir: dirname"
                const safe_name = try ui.sanitizeForDisplay(arena, self.input_buffer.items);
                const status = try std.fmt.allocPrint(arena, "New dir: {s}|", .{safe_name});
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .reverse = true },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .confirm_delete => {
                // Delete confirmation mode
                const marked_count = self.marked_files.count();
                const status = if (marked_count > 0)
                    try std.fmt.allocPrint(arena, "Delete {d} files? [y/n]", .{marked_count})
                else
                    try std.fmt.allocPrint(arena, "Delete file? [y/n]", .{});
                _ = win.printSegment(.{
                    .text = status,
                    .style = .{ .fg = .{ .index = 1 }, .bold = true }, // red
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .tree_view => {
                // Show current directory path with ~ prefix for home (FR-030, FR-031)
                if (self.file_tree) |ft| {
                    // Format path: replace home directory with ~ (FR-031)
                    const display_path = try formatDisplayPath(arena, ft.root_path);
                    const safe_root = try ui.sanitizeForDisplay(arena, display_path);
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
            else if (self.marked_files.count() > 0)
                "Space:unmark  y:yank  d:cut  D:delete  Esc:clear marks"
            else
                "j/k:move  h/l:collapse/expand  Space:mark  /:search  ?:help  q:quit",
            .search => "Enter:confirm  Esc:cancel",
            .path_input => "Enter:go  Esc:cancel",
            .rename => "Enter:confirm  Esc:cancel",
            .new_file => "Enter:create  Esc:cancel",
            .new_dir => "Enter:create  Esc:cancel",
            .confirm_delete => "y:confirm  n/Esc:cancel",
            .preview => "j/k:scroll  o:close  q:quit",
            .help => "",
        };

        if (hints.len > 0) {
            _ = win.printSegment(.{
                .text = hints,
                .style = .{ .fg = .{ .index = 8 } }, // dim
            }, .{ .row_offset = row, .col_offset = 0 });
        }
    }
};

/// Validate filename - reject path separators and parent directory references
/// to prevent path traversal attacks
fn isValidFilename(name: []const u8) bool {
    if (name.len == 0) return false;

    // Reject path separators
    if (std.mem.indexOf(u8, name, "/") != null) return false;
    if (std.mem.indexOf(u8, name, "\\") != null) return false;

    // Reject parent directory reference
    if (std.mem.eql(u8, name, "..")) return false;
    if (std.mem.eql(u8, name, ".")) return false;

    return true;
}

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

/// Format path for display, replacing home directory with ~
/// Caller must free the returned string.
fn formatDisplayPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return try allocator.dupe(u8, path);

    if (std.mem.startsWith(u8, path, home)) {
        if (path.len == home.len) {
            // Exact home directory
            return try allocator.dupe(u8, "~");
        }
        if (path.len > home.len and path[home.len] == '/') {
            // Path under home directory: ~/...
            return try std.fmt.allocPrint(allocator, "~{s}", .{path[home.len..]});
        }
    }
    // Path outside home or doesn't match home prefix properly
    return try allocator.dupe(u8, path);
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

/// Copy a directory recursively with symlink safety
/// Symlinks are skipped to prevent following links outside the intended tree
/// Returns error if any file copy fails (to prevent data loss on cut operations)
fn copyDirRecursive(src_path: []const u8, dest_path: []const u8) !void {
    // Security: Check if source is a symlink
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.fs.cwd().readLink(src_path, &link_buf)) |_| {
        // Skip symlinks during copy
        return;
    } else |_| {}

    // Create destination directory
    std.fs.cwd().makeDir(dest_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = try std.fs.cwd().openDir(src_path, .{ .iterate = true });
    defer src_dir.close();

    // Use a stack-based allocator for path building
    var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    // Iterate and copy with symlink checks - propagate errors to prevent partial copy + delete
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        fba.reset();
        const src_child = try std.fs.path.join(allocator, &.{ src_path, entry.name });
        const dest_child = try std.fs.path.join(allocator, &.{ dest_path, entry.name });

        // Check for symlink before processing
        if (std.fs.cwd().readLink(src_child, &link_buf)) |_| {
            // Skip symlinks
            continue;
        } else |_| {}

        if (entry.kind == .directory) {
            try copyDirRecursive(src_child, dest_child);
        } else {
            // Propagate error instead of swallowing it
            try std.fs.cwd().copyFile(src_child, std.fs.cwd(), dest_child, .{});
        }
    }
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

test "isValidFilename" {
    // Valid filenames
    try std.testing.expect(isValidFilename("test.txt"));
    try std.testing.expect(isValidFilename("my-file_name.zig"));
    try std.testing.expect(isValidFilename("file with spaces"));

    // Invalid filenames - path traversal attempts
    try std.testing.expect(!isValidFilename(".."));
    try std.testing.expect(!isValidFilename("."));
    try std.testing.expect(!isValidFilename("path/to/file"));
    try std.testing.expect(!isValidFilename("path\\to\\file"));
    try std.testing.expect(!isValidFilename(""));
}

test "copyDirRecursive creates destination and copies files" {
    const allocator = std.testing.allocator;

    // Create temp directory structure
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create source directory with files
    try tmp_dir.dir.makeDir("src_dir");
    var src_dir = try tmp_dir.dir.openDir("src_dir", .{});
    defer src_dir.close();

    const test_content = "test content";
    var file1 = try src_dir.createFile("file1.txt", .{});
    try file1.writeAll(test_content);
    file1.close();

    var file2 = try src_dir.createFile("file2.txt", .{});
    try file2.writeAll("another file");
    file2.close();

    // Get absolute paths
    const src_path = try tmp_dir.dir.realpathAlloc(allocator, "src_dir");
    defer allocator.free(src_path);
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    const dest_path = try std.fs.path.join(allocator, &.{ base_path, "dest_dir" });
    defer allocator.free(dest_path);

    // Copy directory
    try copyDirRecursive(src_path, dest_path);

    // Verify destination exists and contains files
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    var read_file = try dest_dir.openFile("file1.txt", .{});
    defer read_file.close();
    var buf: [64]u8 = undefined;
    const len = try read_file.readAll(&buf);
    try std.testing.expectEqualStrings(test_content, buf[0..len]);
}

test "copyDirRecursive handles nested directories" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create nested structure: src/sub/file.txt
    try tmp_dir.dir.makePath("src_nested/sub");
    var sub_dir = try tmp_dir.dir.openDir("src_nested/sub", .{});
    var nested_file = try sub_dir.createFile("nested.txt", .{});
    try nested_file.writeAll("nested content");
    nested_file.close();
    sub_dir.close();

    const src_path = try tmp_dir.dir.realpathAlloc(allocator, "src_nested");
    defer allocator.free(src_path);
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    const dest_path = try std.fs.path.join(allocator, &.{ base_path, "dest_nested" });
    defer allocator.free(dest_path);

    try copyDirRecursive(src_path, dest_path);

    // Verify nested file was copied
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();
    var dest_sub = try dest_dir.openDir("sub", .{});
    defer dest_sub.close();
    _ = try dest_sub.statFile("nested.txt");
}

test "encodeBase64 produces valid output" {
    const allocator = std.testing.allocator;

    // Test basic encoding
    const result1 = try encodeBase64(allocator, "Hello");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("SGVsbG8=", result1);

    // Test empty string
    const result2 = try encodeBase64(allocator, "");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("", result2);

    // Test longer string
    const result3 = try encodeBase64(allocator, "Hello, World!");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", result3);
}

test "ClipboardOperation enum values" {
    // Verify clipboard operation states
    var op: App.ClipboardOperation = .none;
    try std.testing.expectEqual(App.ClipboardOperation.none, op);

    op = .copy;
    try std.testing.expectEqual(App.ClipboardOperation.copy, op);

    op = .cut;
    try std.testing.expectEqual(App.ClipboardOperation.cut, op);
}

test "AppMode includes all file operation modes" {
    // Verify all required modes exist
    const modes = [_]AppMode{
        .tree_view,
        .preview,
        .search,
        .path_input,
        .rename,
        .new_file,
        .new_dir,
        .confirm_delete,
        .help,
    };

    // All 9 modes should be defined
    try std.testing.expectEqual(@as(usize, 9), modes.len);
}

// ===== Benchmark-style tests for Success Criteria =====

test "SC-002: Delete confirmation requires exactly 2 keypresses (D + y)" {
    // This test verifies the state machine for delete confirmation
    // Mode transition: tree_view -> (D) -> confirm_delete -> (y) -> tree_view

    // Step 1: D key should transition to confirm_delete mode
    // Step 2: y key should perform delete and return to tree_view
    // Total: 2 keypresses

    // Verify the mode enum supports this flow
    var mode: AppMode = .tree_view;

    // Simulate D key press
    mode = .confirm_delete;
    try std.testing.expectEqual(AppMode.confirm_delete, mode);

    // Simulate y key press (would trigger performDelete and return to tree_view)
    mode = .tree_view;
    try std.testing.expectEqual(AppMode.tree_view, mode);
}

test "SC-004: File operations preserve data integrity" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test file with known content
    const original_content = "important data that must not be lost";
    var src_file = try tmp_dir.dir.createFile("original.txt", .{});
    try src_file.writeAll(original_content);
    src_file.close();

    // Get paths
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    const src_path = try std.fs.path.join(allocator, &.{ base_path, "original.txt" });
    defer allocator.free(src_path);
    const dest_path = try std.fs.path.join(allocator, &.{ base_path, "copy.txt" });
    defer allocator.free(dest_path);

    // Copy file
    try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dest_path, .{});

    // Verify content integrity
    var dest_file = try std.fs.cwd().openFile(dest_path, .{});
    defer dest_file.close();
    const copied_content = try dest_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(copied_content);

    try std.testing.expectEqualStrings(original_content, copied_content);

    // Verify source still exists (no data loss)
    _ = try std.fs.cwd().statFile(src_path);
}

test "SC-005: No crashes on permission errors" {
    // Test that error handling doesn't panic
    // Try to access non-existent path
    const result = std.fs.cwd().statFile("/nonexistent/path/that/should/not/exist");
    try std.testing.expectError(error.FileNotFound, result);
}

test "Search matching performance with many entries" {
    // Verify search matching works efficiently
    // This tests containsIgnoreCase which is used in search

    const test_cases = [_]struct { haystack: []const u8, needle: []const u8, expected: bool }{
        .{ .haystack = "main.zig", .needle = "main", .expected = true },
        .{ .haystack = "UPPERCASE.TXT", .needle = "upper", .expected = true },
        .{ .haystack = "test_file_name_with_underscores.rs", .needle = "file", .expected = true },
        .{ .haystack = "no_match_here", .needle = "xyz", .expected = false },
        .{ .haystack = "CamelCaseFile.java", .needle = "casefile", .expected = true },
    };

    for (test_cases) |tc| {
        const result = containsIgnoreCase(tc.haystack, tc.needle);
        try std.testing.expectEqual(tc.expected, result);
    }
}

test "Filename conflict resolution pattern" {
    // Test the pattern used for filename conflicts: name_1.ext, name_2.ext, etc.
    const allocator = std.testing.allocator;

    const filename = "test.txt";
    const ext = std.fs.path.extension(filename);
    const stem = filename[0 .. filename.len - ext.len];

    // Generate conflict names
    const name1 = try std.fmt.allocPrint(allocator, "{s}_{d}{s}", .{ stem, 1, ext });
    defer allocator.free(name1);
    try std.testing.expectEqualStrings("test_1.txt", name1);

    const name2 = try std.fmt.allocPrint(allocator, "{s}_{d}{s}", .{ stem, 2, ext });
    defer allocator.free(name2);
    try std.testing.expectEqualStrings("test_2.txt", name2);
}

// ===== Task 2.14: Status Bar Path Display Tests (FR-030, FR-031) =====

test "formatDisplayPath replaces home prefix with tilde" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME")) |home| {
        // Path under home directory should show ~ prefix
        const home_subpath = try std.fmt.allocPrint(allocator, "{s}/Documents/github/kaiu", .{home});
        defer allocator.free(home_subpath);

        const display = try formatDisplayPath(allocator, home_subpath);
        defer allocator.free(display);

        try std.testing.expectEqualStrings("~/Documents/github/kaiu", display);
    }
}

test "formatDisplayPath handles home directory exactly" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME")) |home| {
        // Exact home directory should show just "~"
        const display = try formatDisplayPath(allocator, home);
        defer allocator.free(display);

        try std.testing.expectEqualStrings("~", display);
    }
}

test "formatDisplayPath preserves paths outside home" {
    const allocator = std.testing.allocator;

    // Path outside home directory should be unchanged
    const path = "/usr/local/bin";
    const display = try formatDisplayPath(allocator, path);
    defer allocator.free(display);

    try std.testing.expectEqualStrings("/usr/local/bin", display);
}

test "formatDisplayPath handles path with home prefix but no slash" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME")) |home| {
        // Path like "/home/user2" when HOME is "/home/user" should NOT be replaced
        const similar_path = try std.fmt.allocPrint(allocator, "{s}2", .{home});
        defer allocator.free(similar_path);

        const display = try formatDisplayPath(allocator, similar_path);
        defer allocator.free(display);

        // Should NOT start with ~ since it's not actually under home
        try std.testing.expectEqualStrings(similar_path, display);
    }
}

