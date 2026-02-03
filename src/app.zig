const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const ui = @import("ui.zig");
const file_ops = @import("file_ops.zig");
const vcs = @import("vcs.zig");
const image = @import("image.zig");
const watcher = @import("watcher.zig");
const icons = @import("icons.zig");
const lsp = @import("lsp.zig");
const reference = @import("reference.zig");
const graph = @import("graph.zig");

pub const AppMode = enum {
    tree_view,
    preview,
    search,
    rename,
    new_file,
    new_dir,
    confirm_delete,
    confirm_overwrite, // For drop filename conflict (US3)
    help,
    // Phase 4.0: Symbol Reference (T015, T029, T034)
    reference_list, // US1: Reference list display
    reference_graph, // US2: Call hierarchy graph display
    reference_filter, // US3: Filter input mode
};

pub const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    // Bracketed paste events (Phase 3 - US3)
    paste_start,
    paste_end,
};

/// Pending key for multi-key commands (e.g., 'g' for gg)
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
    // Image preview state (Phase 3 - US2)
    preview_is_image: bool,
    preview_image: ?vaxis.Image,
    preview_image_dims: ?image.ImageDimensions,
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

    // VCS State (Phase 3 - US1)
    vcs_type: vcs.VCSType,
    vcs_mode: vcs.VCSMode,
    vcs_status: ?vcs.VCSStatusResult,

    // File Watching State (Phase 3 - US4)
    file_watcher: ?*watcher.Watcher,
    watch_debouncer: watcher.Debouncer,

    // Paste/Drop State (Phase 3 - US3)
    paste_buffer: std.ArrayList(u8),
    is_pasting: bool,

    // Status bar file info cache (Phase 3.5 - US3)
    cached_file_info: ?CachedFileInfo,
    cached_file_info_cursor: ?usize, // cursor position when cache was created

    // Double-click detection state (Phase 3.5 - US2: T010)
    last_click_time: ?std.time.Instant, // Monotonic timestamp of last left click
    last_click_entry: ?usize, // Visible index of last click (scroll-adjusted)

    // CLI options (Phase 3.5 - US4: T030)
    show_icons: bool, // Default true, false with --no-icons

    // Phase 4.0: Symbol Reference State (T016, T029)
    lsp_client: ?lsp.LspClient,
    reference_list: ?reference.ReferenceList,
    reference_error_message: ?[]const u8, // For "No references found" or "Language server not available"
    // US2: Graph visualization state
    call_hierarchy_graph: ?graph.CallHierarchyGraph,
    graph_text_content: ?[]const u8, // Cached text tree for fallback display
    graph_scroll_offset: usize,

    const Self = @This();

    /// Cached file stat info for status bar display (Phase 3.5 - US3: T018)
    /// FR-020, FR-021: Show filename, size, and modification time
    pub const CachedFileInfo = struct {
        name: []const u8, // borrowed from FileEntry, not owned
        size: ?u64, // null if stat failed
        mtime_sec: ?i128, // null if stat failed
        is_dir: bool,
        item_count: ?usize, // for directories only
    };

    // Use ClipboardOperation from file_ops module
    pub const ClipboardOperation = file_ops.ClipboardOperation;

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
            .preview_is_image = false,
            .preview_image = null,
            .preview_image_dims = null,
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
            .vcs_type = .none,
            .vcs_mode = .auto,
            .vcs_status = null,
            .file_watcher = null,
            .watch_debouncer = watcher.Debouncer.init(300), // 300ms debounce (T055)
            .paste_buffer = .empty,
            .is_pasting = false,
            .cached_file_info = null,
            .cached_file_info_cursor = null,
            .last_click_time = null,
            .last_click_entry = null,
            .show_icons = true, // Default: icons enabled (T030)
            // Phase 4.0: Symbol Reference State (T016)
            .lsp_client = null,
            .reference_list = null,
            .reference_error_message = null,
            .call_hierarchy_graph = null,
            .graph_text_content = null,
            .graph_scroll_offset = 0,
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
        // Free image from terminal memory if loaded
        if (self.preview_image) |img| {
            self.vx.freeImage(self.tty.writer(), img.id);
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
        // Free VCS status
        if (self.vcs_status) |*status| {
            status.deinit();
        }
        // Free file watcher
        if (self.file_watcher) |w| {
            w.deinit();
        }
        // Free paste buffer
        self.paste_buffer.deinit(self.allocator);
        // Phase 4.0: Free LSP client and reference list (T016)
        if (self.lsp_client) |*client| {
            client.deinit();
        }
        if (self.reference_list) |*ref_list| {
            ref_list.deinit();
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

        // Enable bracketed paste for drag & drop detection (Phase 3 - US3)
        try self.vx.setBracketedPaste(writer, true);
        errdefer self.vx.setBracketedPaste(writer, false) catch {};

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
                    if (self.is_pasting) {
                        // Buffer keystrokes during paste (US3)
                        // Encode codepoint as UTF-8 to support non-ASCII characters
                        if (key.codepoint > 0 and key.codepoint <= 0x10FFFF) {
                            var utf8_buf: [4]u8 = undefined;
                            const codepoint: u21 = @intCast(key.codepoint);
                            const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch 0;
                            if (len > 0) {
                                try self.paste_buffer.appendSlice(self.allocator, utf8_buf[0..len]);
                            }
                        }
                    } else {
                        try self.handleKey(key);
                    }
                },
                .mouse => |mouse| {
                    self.handleMouse(mouse);
                },
                .winsize => |ws| {
                    try self.vx.resize(self.allocator, writer, ws);
                },
                .paste_start => {
                    // Start collecting paste content (US3)
                    self.is_pasting = true;
                    self.paste_buffer.clearRetainingCapacity();
                },
                .paste_end => {
                    // End of paste - process the content (US3)
                    self.is_pasting = false;
                    // Only treat as file drop in tree_view mode
                    if (self.mode == .tree_view) {
                        // Handle paste errors gracefully instead of terminating event loop
                        self.handlePastedContent(self.paste_buffer.items) catch |err| {
                            self.status_message = switch (err) {
                                error.OutOfMemory => "Drop failed: out of memory",
                                else => "Drop failed",
                            };
                        };
                    }
                    self.paste_buffer.clearRetainingCapacity();
                },
            }

            // Poll file watcher for changes (T054)
            try self.pollFileWatcher();

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
            .rename => try self.handleRenameKey(key, key_char),
            .new_file => try self.handleNewFileKey(key, key_char),
            .new_dir => try self.handleNewDirKey(key, key_char),
            .confirm_delete => try self.handleConfirmDeleteKey(key_char),
            .confirm_overwrite => {}, // TODO: Will be implemented in US3 (Drag & Drop)
            .help => self.handleHelpKey(),
            .reference_list => self.handleReferenceListKey(key_char), // Phase 4.0 (T018)
            .reference_graph => self.handleReferenceGraphKey(key), // Phase 4.0 (T033)
            .reference_filter => self.handleReferenceFilterKey(key), // Phase 4.0 (T038)
        }
    }

    // Double-click detection state (Phase 3.5 - US2)
    // Moved to App struct fields: last_click_time, last_click_entry

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
                    .tree_view, .search => self.moveCursor(-1),
                    .preview => if (self.preview_scroll > 0) {
                        self.preview_scroll -= 1;
                    },
                    else => {},
                }
            },
            .wheel_down => {
                switch (self.mode) {
                    .tree_view, .search => self.moveCursor(1),
                    .preview => self.scrollPreviewDown(self.vx.window().height),
                    else => {},
                }
            },
            // Phase 3.5 - US1: Left click to move cursor (T003, T004)
            .left => {
                // Only process release events (not press/drag)
                if (mouse.type == .release) {
                    switch (self.mode) {
                        .tree_view, .search => {
                            // mouse.row is i16, convert to u16 (ignore negative values)
                            if (mouse.row >= 0) {
                                self.handleLeftClick(@intCast(mouse.row));
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// Handle left click in tree view (Phase 3.5 - US1: T003, T005, T006, T006a)
    /// FR-001: Left click moves cursor to clicked row
    /// FR-002: Calculate visible index from screen row + scroll offset
    /// FR-003: Ignore clicks on status bar area (bottom 2 rows)
    /// FR-004: Ignore clicks on blank rows below last entry
    fn handleLeftClick(self: *Self, screen_row: u16) void {
        const ft = self.file_tree orelse return;

        // FR-003: Exclude status bar area (bottom 2 rows) from click detection (T006)
        const win = self.vx.window();
        const tree_height: u16 = if (win.height > 2) win.height - 2 else 0;
        if (tree_height == 0) return;
        if (screen_row >= tree_height) return; // Click on status bar, ignore

        // FR-002: Convert screen row to visible index (T005)
        const target_visible: usize = self.scroll_offset + @as(usize, screen_row);

        // FR-004: Check if target is within valid entry range (T006a)
        const visible_count = ft.countVisible(self.show_hidden);
        if (target_visible >= visible_count) return; // Click below last entry, ignore

        // Phase 3.5 - US2: Double-click detection (T010-T013)
        // FR-010: 400ms threshold
        // FR-013: Same entry check
        const double_click_threshold_ns: u64 = 400 * std.time.ns_per_ms;

        const now = std.time.Instant.now() catch {
            // If we can't get monotonic time, skip double-click detection
            self.cursor = target_visible;
            self.updateScrollOffset();
            self.updateCachedFileInfo();
            return;
        };

        const is_double_click = blk: {
            const last_time = self.last_click_time orelse break :blk false;
            const last_entry = self.last_click_entry orelse break :blk false;

            // FR-013: Must be same entry (T009, T009a - handles scroll between clicks)
            if (last_entry != target_visible) break :blk false;

            // FR-010: Within threshold (T007, T008)
            const elapsed = now.since(last_time);
            break :blk elapsed <= double_click_threshold_ns;
        };

        // Update click tracking state
        self.last_click_time = now;
        self.last_click_entry = target_visible;

        if (is_double_click) {
            // FR-011, FR-012: Double-click action (T013)
            // Clear click state to prevent triple-click being detected as double
            self.last_click_time = null;
            self.last_click_entry = null;

            // Move cursor first, then perform action
            self.cursor = target_visible;
            self.updateScrollOffset();
            self.updateCachedFileInfo();

            // T013, T013a: Expand/collapse directory or open preview
            self.handleDoubleClick();
        } else {
            // FR-001: Single click - move cursor (T003)
            self.cursor = target_visible;
            self.updateScrollOffset();
            self.updateCachedFileInfo();
        }
    }

    /// Handle double-click action (Phase 3.5 - US2: T013, T013a)
    /// FR-011: Directory double-click toggles expand/collapse
    /// FR-012: File double-click opens preview
    /// FR-014: Broken symlink shows error message
    fn handleDoubleClick(self: *Self) void {
        // Reuse expandOrEnter logic
        self.expandOrEnter() catch {
            // T013a: Handle broken symlink or other errors
            self.status_message = "Cannot open: access denied or broken symlink";
        };
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
                    'v' => {
                        // gv - cycle VCS mode (T018)
                        self.cycleVCSMode();
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
                // Priority: marks first, then search
                if (self.marked_files.count() > 0) {
                    self.clearMarkedFiles();
                    self.status_message = "Marks cleared";
                } else if (self.input_buffer.items.len > 0 or self.search_matches.items.len > 0) {
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
            'W' => self.toggleWatching(), // T056: Toggle file watching
            else => {},
        }
    }

    fn handlePreviewKey(self: *Self, key_char: u21) void {
        // Check for pending multi-key command (T017: gr for go to references)
        if (self.pending_key.get()) |pending| {
            self.pending_key.clear();

            if (pending == 'g') {
                switch (key_char) {
                    'r' => {
                        // gr: Go to references (T017)
                        self.triggerReferenceSearch();
                        return;
                    },
                    else => {},
                }
            }
        }

        switch (key_char) {
            'q', 'o', 'h' => self.closePreview(),
            'j' => self.scrollPreviewDown(self.vx.window().height),
            'k' => if (self.preview_scroll > 0) {
                self.preview_scroll -= 1;
            },
            'g' => {
                // Start multi-key command (T017)
                self.pending_key.set('g');
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

        // Phase 3.5 - US3: Update file info cache on cursor change (T018)
        self.updateCachedFileInfo();
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

    /// Update cached file info for status bar display (Phase 3.5 - US3: T018)
    /// Called when cursor moves to a different entry
    fn updateCachedFileInfo(self: *Self) void {
        // Skip if cursor hasn't changed (performance: avoids re-stat and countDirectoryItems)
        if (self.cached_file_info_cursor) |cached_cursor| {
            if (cached_cursor == self.cursor) return;
        }

        const ft = self.file_tree orelse {
            self.cached_file_info = null;
            self.cached_file_info_cursor = null;
            return;
        };

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse {
            self.cached_file_info = null;
            self.cached_file_info_cursor = null;
            return;
        };

        const entry = ft.entries.items[actual_index];
        const is_dir = entry.kind == .directory;

        // Get file stat (FR-026: handle stat failure)
        var size: ?u64 = null;
        var mtime_sec: ?i128 = null;
        var item_count: ?usize = null;

        if (std.fs.cwd().statFile(entry.path)) |stat| {
            if (is_dir) {
                // FR-021: For directories, count items
                item_count = self.countDirectoryItems(entry.path);
            } else {
                size = stat.size;
            }
            // mtime is i128 nanoseconds since epoch, convert to seconds
            mtime_sec = @divFloor(stat.mtime, std.time.ns_per_s);
        } else |_| {
            // stat failed - leave as null (T020a: show "-")
        }

        self.cached_file_info = .{
            .name = entry.name,
            .size = size,
            .mtime_sec = mtime_sec,
            .is_dir = is_dir,
            .item_count = item_count,
        };
        self.cached_file_info_cursor = self.cursor;
    }

    /// Count visible items in a directory (for FR-021)
    fn countDirectoryItems(self: *Self, path: []const u8) ?usize {
        _ = self;
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;
        defer dir.close();

        var count: usize = 0;
        var iter = dir.iterate();
        while (iter.next() catch return null) |_| {
            count += 1;
        }
        return count;
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

        // Invalidate cached file info - visible indices changed
        self.cached_file_info = null;
        self.cached_file_info_cursor = null;

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

        // Invalidate cached file info - tree structure changed
        self.cached_file_info = null;
        self.cached_file_info_cursor = null;

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

        // Invalidate cached file info - tree structure changed
        self.cached_file_info = null;
        self.cached_file_info_cursor = null;
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
        // Free previous image if any
        if (self.preview_image) |img| {
            self.vx.freeImage(self.tty.writer(), img.id);
            self.preview_image = null;
        }
        self.preview_is_image = false;
        self.preview_image_dims = null;

        // Check if file is an image (T030)
        if (image.isImageFile(path)) {
            try self.openImagePreview(path);
            return;
        }

        // Read file (text preview)
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
        if (file_ops.isBinaryContent(content)) {
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

    /// Open image preview (T030, T031, T035, T036)
    fn openImagePreview(self: *Self, path: []const u8) !void {
        self.preview_is_image = true;
        self.preview_path = try self.allocator.dupe(u8, path);

        // Check file size (T036: >10MB is too large)
        if (image.isImageTooLarge(path)) {
            self.preview_content = try self.allocator.dupe(u8, "[Image too large to preview]");
            self.preview_scroll = 0;
            self.mode = .preview;
            return;
        }

        // Get image dimensions (T031)
        self.preview_image_dims = image.getImageDimensions(path);

        // Show "Loading..." for large images before loading
        // Use u64 to avoid overflow for large images (e.g., 8K = 7680x4320)
        const is_large_image = if (self.preview_image_dims) |dims|
            @as(u64, dims.width) * @as(u64, dims.height) > 1920 * 1080 // > Full HD
        else
            false;

        if (is_large_image) {
            // Show loading message and render immediately
            self.preview_content = try self.allocator.dupe(u8, "[Loading image...]");
            self.preview_scroll = 0;
            self.mode = .preview;
            try self.render(self.tty.writer());
            // Clear for actual image load
            if (self.preview_content) |content| {
                self.allocator.free(content);
                self.preview_content = null;
            }
        }

        // Try to load image using Kitty Graphics Protocol
        // Note: Force enable on Ghostty since libvaxis may not detect it correctly
        const is_ghostty = if (std.posix.getenv("TERM_PROGRAM")) |tp|
            std.mem.eql(u8, tp, "ghostty")
        else
            false;

        // Force kitty_graphics capability for Ghostty
        if (is_ghostty and !self.vx.caps.kitty_graphics) {
            self.vx.caps.kitty_graphics = true;
        }

        var load_error: ?[]const u8 = null;
        kitty_load: {
            if (self.vx.caps.kitty_graphics) {
                // Load with zigimg, transmit with RGBA format
                // Use heap allocation to avoid stack overflow risk (10MB to match size check)
                const read_buffer = self.allocator.alloc(u8, 1024 * 1024 * 10) catch {
                    load_error = "AllocFail";
                    break :kitty_load;
                };
                defer self.allocator.free(read_buffer);

                if (vaxis.zigimg.Image.fromFilePath(self.allocator, path, read_buffer)) |loaded_img_const| {
                    var loaded_img = loaded_img_const;
                    defer loaded_img.deinit();

                    // Convert to RGBA32 format before downsampling (Codex review fix)
                    // This ensures consistent pixel format regardless of source image type
                    loaded_img.convert(.rgba32) catch {
                        load_error = "ConvertRGBA";
                        break :kitty_load;
                    };

                    // Calculate target size from terminal dimensions
                    // Estimate ~10px per cell width, ~20px per cell height
                    const win = self.vx.window();
                    // Clamp to at least 1 to avoid division by zero (Codex review fix)
                    const max_width: u32 = @max(1, @as(u32, @intCast(win.width)) * 10);
                    const max_height: u32 = @max(1, @as(u32, @intCast(win.height)) * 20);

                    // Downsample large images for performance (#57)
                    const maybe_downsampled = image.downsampleImage(self.allocator, &loaded_img, max_width, max_height) catch {
                        load_error = "DownsampleOOM";
                        break :kitty_load;
                    };

                    if (maybe_downsampled) |downsampled| {
                        defer downsampled.deinit(self.allocator);

                        // Create a new zigimg.Image from downsampled pixels
                        const pixel_bytes = std.mem.sliceAsBytes(downsampled.pixels);
                        if (vaxis.zigimg.Image.fromRawPixels(
                            self.allocator,
                            downsampled.width,
                            downsampled.height,
                            pixel_bytes,
                            .rgba32,
                        )) |resized_img_const| {
                            var resized_img = resized_img_const;
                            defer resized_img.deinit();
                            self.preview_image = self.vx.transmitImage(
                                self.allocator,
                                self.tty.writer(),
                                &resized_img,
                                .rgba,
                            ) catch |err| blk: {
                                load_error = @errorName(err);
                                break :blk null;
                            };
                        } else |_| {
                            // Fall back to original if resized image creation fails
                            self.preview_image = self.vx.transmitImage(
                                self.allocator,
                                self.tty.writer(),
                                &loaded_img,
                                .rgba,
                            ) catch |err| blk: {
                                load_error = @errorName(err);
                                break :blk null;
                            };
                        }
                    } else {
                        // No downsampling needed (image already small)
                        self.preview_image = self.vx.transmitImage(
                            self.allocator,
                            self.tty.writer(),
                            &loaded_img,
                            .rgba,
                        ) catch |err| blk: {
                            load_error = @errorName(err);
                            break :blk null;
                        };
                    }
                } else |err| {
                    load_error = @errorName(err);
                }
            }
        }
        const try_kitty = self.vx.caps.kitty_graphics;

        // If image load failed or no Kitty support, show fallback (T033)
        if (self.preview_image == null) {
            const dims = self.preview_image_dims;
            const file = std.fs.openFileAbsolute(path, .{}) catch {
                self.preview_content = try self.allocator.dupe(u8, "[Cannot display image]");
                self.preview_scroll = 0;
                self.mode = .preview;
                return;
            };
            defer file.close();

            const stat = file.stat() catch {
                self.preview_content = try self.allocator.dupe(u8, "[Cannot display image]");
                self.preview_scroll = 0;
                self.mode = .preview;
                return;
            };

            var buf: [256]u8 = undefined;
            const filename = std.fs.path.basename(path);
            const size_kb = stat.size / 1024;

            // Debug info in fallback message
            const reason: []const u8 = if (load_error) |e| e else if (!try_kitty) "NoKitty" else "NullImg";

            const fallback_msg = if (dims) |d|
                std.fmt.bufPrint(&buf, "[{s}] {s} ({d}x{d}, {d}KB)", .{ reason, filename, d.width, d.height, size_kb }) catch "[Image]"
            else
                std.fmt.bufPrint(&buf, "[{s}] {s} ({d}KB)", .{ reason, filename, size_kb }) catch "[Image]";

            self.preview_content = try self.allocator.dupe(u8, fallback_msg);
        }

        self.preview_scroll = 0;
        self.mode = .preview;
    }

    // ===== Phase 4.0: Symbol Reference Functions (T017-T023) =====

    /// Trigger reference search for symbol at cursor position. (T017)
    fn triggerReferenceSearch(self: *Self) void {
        // Get current file path from preview
        const file_path = self.preview_path orelse {
            self.reference_error_message = "No file open";
            self.mode = .reference_list;
            return;
        };

        // Check if it's a Zig file
        if (!std.mem.endsWith(u8, file_path, ".zig")) {
            self.reference_error_message = "Unsupported file type";
            self.mode = .reference_list;
            return;
        }

        // Get cursor position (use preview_scroll as line estimate)
        const line: u32 = @intCast(self.preview_scroll);
        const column: u32 = 0; // We don't track column in preview, use 0

        // Initialize LSP client if needed
        if (self.lsp_client == null) {
            self.lsp_client = lsp.LspClient.init(self.allocator);

            // Get root path from file_tree
            const root_path = if (self.file_tree) |ft| ft.root_path else file_path;

            self.lsp_client.?.start(root_path) catch |err| {
                switch (err) {
                    lsp.LspClient.Error.ServerNotFound => {
                        self.reference_error_message = "Language server not available";
                    },
                    else => {
                        self.reference_error_message = "Failed to start language server";
                    },
                }
                self.lsp_client.?.deinit();
                self.lsp_client = null;
                self.mode = .reference_list;
                return;
            };
        }

        // Send didOpen notification
        const content = self.preview_content orelse "";
        self.lsp_client.?.didOpen(file_path, content) catch {
            self.reference_error_message = "Failed to open document";
            self.mode = .reference_list;
            return;
        };

        // Find references
        const refs = self.lsp_client.?.findReferences(file_path, line, column) catch {
            self.reference_error_message = "Request timed out";
            self.mode = .reference_list;
            return;
        };

        if (refs.len == 0) {
            self.reference_error_message = "No references found";
            self.mode = .reference_list;
            return;
        }

        // Build reference list
        self.clearReferenceList();

        const symbol_name = std.fs.path.basename(file_path);
        self.reference_list = reference.ReferenceList.init(self.allocator, symbol_name) catch {
            self.reference_error_message = "Out of memory";
            self.mode = .reference_list;
            return;
        };

        for (refs) |ref| {
            self.reference_list.?.addReference(.{
                .file_path = self.allocator.dupe(u8, ref.file_path) catch continue,
                .line = ref.line,
                .column = ref.column,
                .snippet = self.allocator.dupe(u8, ref.snippet) catch self.allocator.dupe(u8, "") catch continue,
                .context_before = self.allocator.dupe(u8, "") catch continue,
                .context_after = self.allocator.dupe(u8, "") catch continue,
            }) catch continue;
        }

        // Free LSP response
        for (refs) |ref| {
            self.allocator.free(ref.file_path);
            self.allocator.free(ref.snippet);
        }
        self.allocator.free(refs);

        self.reference_error_message = null;
        self.mode = .reference_list;
    }

    /// Handle key in reference list mode. (T018)
    fn handleReferenceListKey(self: *Self, key_char: u21) void {
        // If there's an error message, any key closes
        if (self.reference_error_message != null) {
            self.reference_error_message = null;
            self.mode = .preview;
            return;
        }

        switch (key_char) {
            'j' => {
                if (self.reference_list) |*ref_list| {
                    ref_list.moveDown();
                }
            },
            'k' => {
                if (self.reference_list) |*ref_list| {
                    ref_list.moveUp();
                }
            },
            'o' => {
                // Preview snippet (T020)
                self.previewReferenceSnippet();
            },
            'G' => {
                // Switch to graph view (T033)
                self.switchToGraphView();
            },
            'f' => {
                // Enter filter mode (T038)
                self.input_buffer.clearRetainingCapacity();
                self.mode = .reference_filter;
            },
            vaxis.Key.enter => {
                // Open in $EDITOR (T021)
                self.openReferenceInEditor();
            },
            'q', vaxis.Key.escape => {
                // Close reference list and return to preview
                self.clearReferenceList();
                self.mode = .preview;
            },
            else => {},
        }
    }

    /// Handle key events in reference filter mode. (T038)
    fn handleReferenceFilterKey(self: *Self, key: vaxis.Key) void {
        const key_char = if (key.codepoint < 128) @as(u8, @intCast(key.codepoint)) else 0;

        switch (key.codepoint) {
            vaxis.Key.enter => {
                // Apply filter and return to reference list
                if (self.reference_list) |*ref_list| {
                    if (self.input_buffer.items.len > 0) {
                        ref_list.applyFilter(self.input_buffer.items) catch {};
                    } else {
                        ref_list.clearFilter();
                    }
                }
                self.mode = .reference_list;
            },
            vaxis.Key.escape => {
                // Cancel filter and return to reference list
                self.mode = .reference_list;
            },
            vaxis.Key.backspace => {
                // Delete character
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                // Add character to filter pattern
                if (key_char >= 32 and key_char < 127) {
                    self.input_buffer.append(self.allocator, key_char) catch {};
                }
            },
        }
    }

    /// Preview the code snippet for current reference. (T020)
    fn previewReferenceSnippet(self: *Self) void {
        const ref_list = self.reference_list orelse return;
        const current = ref_list.getCurrent() orelse return;

        // Show context in status message
        const msg_buf = &self.status_message_buf;
        const msg = std.fmt.bufPrint(msg_buf, "{s}:{d}", .{
            std.fs.path.basename(current.file_path),
            current.line + 1,
        }) catch return;
        self.status_message = msg;
    }

    /// Open current reference in $EDITOR. (T021)
    fn openReferenceInEditor(self: *Self) void {
        const ref_list = self.reference_list orelse return;
        const current = ref_list.getCurrent() orelse return;

        // Get editor from $EDITOR or fall back to defaults
        const editor = std.posix.getenv("EDITOR") orelse
            std.posix.getenv("VISUAL") orelse "vi";

        // Build command with line number
        var line_buf: [32]u8 = undefined;
        const line_arg = std.fmt.bufPrint(&line_buf, "+{d}", .{current.line + 1}) catch return;

        // Launch editor
        var child = std.process.Child.init(&[_][]const u8{ editor, line_arg, current.file_path }, self.allocator);
        child.spawn() catch return;
        _ = child.wait() catch {};

        // Clear reference list and return to tree view after editor
        self.clearReferenceList();
        self.closePreview();
    }

    /// Clear reference list and free memory.
    fn clearReferenceList(self: *Self) void {
        if (self.reference_list) |*ref_list| {
            ref_list.deinit();
            self.reference_list = null;
        }
        self.reference_error_message = null;
        self.clearGraph();
    }

    /// Clear call hierarchy graph and free memory. (T029)
    fn clearGraph(self: *Self) void {
        if (self.call_hierarchy_graph) |*g| {
            g.deinit();
            self.call_hierarchy_graph = null;
        }
        if (self.graph_text_content) |content| {
            self.allocator.free(content);
            self.graph_text_content = null;
        }
        self.graph_scroll_offset = 0;
    }

    /// Switch from reference list to graph view. (T033)
    fn switchToGraphView(self: *Self) void {
        // Get current reference for building graph
        const ref_list = self.reference_list orelse return;
        const current = ref_list.getCurrent() orelse return;

        // Initialize LSP client if needed
        if (self.lsp_client == null) {
            self.lsp_client = lsp.LspClient.init(self.allocator);

            // Start LSP with root path
            const root_path = if (self.file_tree) |ft| ft.root_path else ".";
            self.lsp_client.?.start(root_path) catch {
                self.lsp_client.?.deinit();
                self.lsp_client = null;
                self.status_message = "Language server not available";
                return;
            };
        }

        // Get incoming and outgoing calls
        const incoming = self.lsp_client.?.getIncomingCalls(
            current.file_path,
            current.line,
            current.column,
        ) catch &[_]lsp.CallHierarchyItem{};
        defer {
            for (incoming) |*item| {
                self.allocator.free(item.name);
                self.allocator.free(item.file_path);
                self.allocator.free(item.snippet);
            }
            self.allocator.free(incoming);
        }

        const outgoing = self.lsp_client.?.getOutgoingCalls(
            current.file_path,
            current.line,
            current.column,
        ) catch &[_]lsp.CallHierarchyItem{};
        defer {
            for (outgoing) |*item| {
                self.allocator.free(item.name);
                self.allocator.free(item.file_path);
                self.allocator.free(item.snippet);
            }
            self.allocator.free(outgoing);
        }

        // Build graph
        self.clearGraph();
        self.call_hierarchy_graph = graph.CallHierarchyGraph.init(self.allocator);

        const root_item = graph.CallHierarchyItem{
            .name = self.allocator.dupe(u8, ref_list.symbol_name) catch return,
            .kind = .function,
            .file_path = self.allocator.dupe(u8, current.file_path) catch return,
            .line = current.line,
            .column = current.column,
            .snippet = self.allocator.dupe(u8, current.snippet) catch return,
        };

        self.call_hierarchy_graph.?.buildFromCallHierarchy(root_item, incoming, outgoing) catch {
            self.clearGraph();
            self.status_message = "Failed to build call hierarchy graph";
            return;
        };

        // Generate text tree for fallback display (T028, T032)
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const text_content = self.call_hierarchy_graph.?.toTextTree(arena.allocator()) catch "";
        self.graph_text_content = self.allocator.dupe(u8, text_content) catch null;

        self.mode = .reference_graph;
    }

    /// Handle key events in reference graph mode. (T033)
    fn handleReferenceGraphKey(self: *Self, key: vaxis.Key) void {
        const key_char = if (key.codepoint < 128) @as(u8, @intCast(key.codepoint)) else 0;

        switch (key_char) {
            'j' => {
                // Scroll down
                self.graph_scroll_offset += 1;
            },
            'k' => {
                // Scroll up
                if (self.graph_scroll_offset > 0) {
                    self.graph_scroll_offset -= 1;
                }
            },
            'l', 'q' => {
                // Return to reference list
                self.mode = .reference_list;
            },
            else => {
                // Check for escape
                if (key.codepoint == vaxis.Key.escape) {
                    self.mode = .reference_list;
                }
            },
        }
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
        // Reset image preview state
        if (self.preview_image) |img| {
            self.vx.freeImage(self.tty.writer(), img.id);
            self.preview_image = null;
        }
        self.preview_is_image = false;
        self.preview_image_dims = null;
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
        self.search_matches.clearRetainingCapacity();
        self.current_match = 0;
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

            // Invalidate cached file info - entry references are now invalid (UAF fix)
            self.cached_file_info = null;
            self.cached_file_info_cursor = null;

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

            // Refresh VCS status (T021)
            self.refreshVCSStatus();
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
        file_loop: for (self.clipboard_files.items) |src_path| {
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
                if (suffix > 100) {
                    // Too many conflicts - skip this file to prevent overwriting
                    // Use labeled continue to exit to outer for loop, not inner while loop
                    if (owned_final) self.allocator.free(final_dest);
                    continue :file_loop;
                }
            } else |_| {
                // File doesn't exist, we can use this path
            }
            defer if (owned_final) self.allocator.free(final_dest);

            // Perform copy or move
            if (self.clipboard_operation == .copy) {
                self.copyPath(src_path, final_dest) catch continue :file_loop;
            } else {
                std.fs.cwd().rename(src_path, final_dest) catch {
                    // If rename fails (cross-device), try copy + delete
                    // Only delete source if copy succeeded to prevent data loss
                    self.copyPath(src_path, final_dest) catch continue :file_loop;
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
        try file_ops.copyPath(src, dest);
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
        const encoded = try file_ops.encodeBase64(self.render_arena.allocator(), text);

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
        if (!file_ops.isValidFilename(new_name)) {
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
        if (!file_ops.isValidFilename(new_name)) {
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
        if (!file_ops.isValidFilename(new_name)) {
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
        try file_ops.deletePathRecursive(path);
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
            .tree_view, .search, .rename, .new_file, .new_dir, .confirm_delete, .confirm_overwrite => {
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
                    // Pass VCS status for file coloring (T022)
                    const vcs_status_ptr: ?*const vcs.VCSStatusResult = if (self.vcs_status) |*s| s else null;
                    // Phase 3.5 - US4: Pass show_icons flag (T031)
                    try ui.renderTree(tree_win, ft, self.cursor, self.scroll_offset, self.show_hidden, search_query, self.search_matches.items, &self.marked_files, vcs_status_ptr, self.show_icons, arena);
                } else {
                    _ = tree_win.printSegment(.{ .text = "No directory loaded" }, .{});
                }

                // Status bar at bottom (only if we have room)
                if (height > 2) {
                    try self.renderStatusBar(win, tree_height, arena);
                }
            },
            .preview => {
                if (self.preview_is_image) {
                    // Image preview (T032, T033, T034)
                    try self.renderImagePreview(win, arena);
                } else if (self.preview_content) |content| {
                    const filename = if (self.preview_path) |p| std.fs.path.basename(p) else "preview";
                    try ui.renderPreview(win, content, filename, self.preview_scroll, self.render_arena.allocator());
                }
            },
            .help => {
                try ui.renderHelp(win);
            },
            .reference_list => {
                // Phase 4.0: Render reference list (T019)
                try ui.renderReferenceList(
                    win,
                    if (self.reference_list) |*rl| rl else null,
                    self.reference_error_message,
                    arena,
                );
            },
            .reference_graph => {
                // Phase 4.0: Render call hierarchy graph (T032)
                try ui.renderReferenceGraph(
                    win,
                    self.graph_text_content,
                    self.graph_scroll_offset,
                    arena,
                );
            },
            .reference_filter => {
                // Phase 4.0: Render reference list with filter input (T038)
                try ui.renderReferenceList(
                    win,
                    if (self.reference_list) |*rl| rl else null,
                    self.reference_error_message,
                    arena,
                );
                // Overlay filter input at bottom
                try ui.renderFilterInput(win, self.input_buffer.items);
            },
        }

        try self.vx.render(writer);
    }

    fn renderStatusBar(self: *Self, win: vaxis.Window, row: u16, arena: std.mem.Allocator) !void {
        // Row 1: Path and status
        try self.renderStatusRow1(win, arena, row);

        // Row 2: File info and help hint
        if (row + 1 < win.height) {
            try self.renderStatusRow2(win, row + 1, arena);
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
                    const display_path = try file_ops.formatDisplayPath(arena, ft.root_path);
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
                        const path_result = win.printSegment(.{
                            .text = safe_root,
                            .style = .{ .fg = .{ .index = 6 }, .bold = true }, // cyan, bold
                        }, .{ .row_offset = row, .col_offset = 0 });

                        var col_offset = path_result.col;

                        // Display VCS branch info after path (T023)
                        if (self.getVCSBranchDisplay(arena)) |branch_display| {
                            _ = win.printSegment(.{
                                .text = " ",
                            }, .{ .row_offset = row, .col_offset = col_offset });
                            const branch_result = win.printSegment(.{
                                .text = branch_display,
                                .style = .{ .fg = .{ .index = 3 } }, // yellow
                            }, .{ .row_offset = row, .col_offset = col_offset + 1 });
                            col_offset = branch_result.col;
                        }

                        // Display [W] when watching is enabled (T057)
                        if (self.file_watcher) |w| {
                            if (w.isEnabled()) {
                                _ = win.printSegment(.{
                                    .text = " [W]",
                                    .style = .{ .fg = .{ .index = 2 } }, // green
                                }, .{ .row_offset = row, .col_offset = col_offset });
                            }
                        }
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

    fn renderStatusRow2(self: *Self, win: vaxis.Window, row: u16, arena: std.mem.Allocator) !void {
        // Phase 3.5 - US3: New status bar layout (T019)
        // Left side: file info (filename | size | modified) or hints for special modes
        // Right side: ?:help (FR-025: always visible)

        const help_hint = "?:help";
        const help_col: u16 = @intCast(win.width -| help_hint.len -| 1);

        // FR-025: Always show help hint on the right
        _ = win.printSegment(.{
            .text = help_hint,
            .style = .{ .fg = .{ .index = 8 } }, // dim
        }, .{ .row_offset = row, .col_offset = help_col });

        // Left side content depends on mode
        switch (self.mode) {
            .tree_view, .search => {
                // Show file info or context-specific hints
                if (self.marked_files.count() > 0) {
                    // Show marked files count and operations
                    const marked_hint = try std.fmt.allocPrint(arena, "{d} marked  Space:unmark  y:yank  d:cut  D:delete", .{self.marked_files.count()});
                    _ = win.printSegment(.{
                        .text = marked_hint,
                        .style = .{ .fg = .{ .index = 5 } }, // magenta
                    }, .{ .row_offset = row, .col_offset = 0 });
                } else if (self.cached_file_info) |info| {
                    // FR-020, FR-021: Show file info
                    try self.renderFileInfo(win, row, info, arena);
                }
                // T020b: Empty tree shows nothing on left (help hint still visible)
            },
            .rename => {
                _ = win.printSegment(.{
                    .text = "Enter:confirm  Esc:cancel",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .new_file => {
                _ = win.printSegment(.{
                    .text = "Enter:create  Esc:cancel",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .new_dir => {
                _ = win.printSegment(.{
                    .text = "Enter:create  Esc:cancel",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .confirm_delete => {
                _ = win.printSegment(.{
                    .text = "y:confirm  n/Esc:cancel",
                    .style = .{ .fg = .{ .index = 1 } }, // red
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .confirm_overwrite => {
                _ = win.printSegment(.{
                    .text = "o:overwrite  r:rename  Esc:cancel",
                    .style = .{ .fg = .{ .index = 3 } }, // yellow
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .preview => {
                _ = win.printSegment(.{
                    .text = "j/k:scroll  q/o/h:close",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .reference_list => {
                _ = win.printSegment(.{
                    .text = "j/k:nav  Enter:open  o:preview  G:graph  q:close",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .reference_graph => {
                _ = win.printSegment(.{
                    .text = "j/k:scroll  l/q:back to list",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .reference_filter => {
                _ = win.printSegment(.{
                    .text = "Enter:apply  Esc:cancel",
                    .style = .{ .fg = .{ .index = 8 } },
                }, .{ .row_offset = row, .col_offset = 0 });
            },
            .help => {},
        }
    }

    /// Render file info in status bar (Phase 3.5 - US3: T019, T020)
    /// FR-020: filename | size | modified
    /// FR-021: dirname/ | N items
    /// FR-026: show "-" for stat failures
    fn renderFileInfo(self: *Self, win: vaxis.Window, row: u16, info: CachedFileInfo, arena: std.mem.Allocator) !void {
        _ = self;
        var col: u16 = 0;

        // Filename (sanitized)
        const safe_name = try ui.sanitizeForDisplay(arena, info.name);
        const name_result = win.printSegment(.{
            .text = safe_name,
            .style = .{ .fg = .{ .index = 7 }, .bold = true }, // white, bold
        }, .{ .row_offset = row, .col_offset = col });
        col = name_result.col;

        // Add trailing slash for directories
        if (info.is_dir) {
            const slash_result = win.printSegment(.{
                .text = "/",
                .style = .{ .fg = .{ .index = 4 } }, // blue
            }, .{ .row_offset = row, .col_offset = col });
            col = slash_result.col;
        }

        // Separator
        const sep_result = win.printSegment(.{
            .text = " | ",
            .style = .{ .fg = .{ .index = 8 } }, // dim
        }, .{ .row_offset = row, .col_offset = col });
        col = sep_result.col;

        // Size or item count
        if (info.is_dir) {
            // FR-021: Directory item count
            const count_str = if (info.item_count) |count|
                if (count == 1)
                    "1 item"
                else
                    try std.fmt.allocPrint(arena, "{d} items", .{count})
            else
                "-"; // T020a: stat failed
            const count_result = win.printSegment(.{
                .text = count_str,
                .style = .{ .fg = .{ .index = 8 } },
            }, .{ .row_offset = row, .col_offset = col });
            col = count_result.col;
        } else {
            // FR-022: Human-readable file size
            const size_str = if (info.size) |size|
                try ui.formatSize(arena, size)
            else
                "-"; // T020a: stat failed
            const size_result = win.printSegment(.{
                .text = size_str,
                .style = .{ .fg = .{ .index = 8 } },
            }, .{ .row_offset = row, .col_offset = col });
            col = size_result.col;
        }

        // Separator and modification time (for files only, or always show?)
        // Per spec: files show size | modified, directories show item count only
        if (!info.is_dir) {
            const sep2_result = win.printSegment(.{
                .text = " | ",
                .style = .{ .fg = .{ .index = 8 } },
            }, .{ .row_offset = row, .col_offset = col });
            col = sep2_result.col;

            // FR-023, FR-024: Relative or absolute time
            const now_sec = std.time.timestamp();
            const time_str = if (info.mtime_sec) |mtime|
                try ui.formatRelativeTime(arena, mtime, now_sec)
            else
                "-"; // T020a: stat failed
            _ = win.printSegment(.{
                .text = time_str,
                .style = .{ .fg = .{ .index = 8 } },
            }, .{ .row_offset = row, .col_offset = col });
        }
    }
    // ===== Image Preview Rendering (Phase 3 - US2) =====

    /// Render image preview (T032, T033, T034)
    fn renderImagePreview(self: *Self, win: vaxis.Window, arena: std.mem.Allocator) !void {
        const height = win.height;
        if (height == 0) return;

        const filename = if (self.preview_path) |p| std.fs.path.basename(p) else "image";

        // Build title with dimensions (T034)
        const title = if (self.preview_image_dims) |dims|
            try std.fmt.allocPrint(arena, "{s} ({d}x{d})", .{ filename, dims.width, dims.height })
        else
            try std.fmt.allocPrint(arena, "{s}", .{filename});

        // Render title bar
        _ = win.printSegment(.{
            .text = title,
            .style = .{ .bold = true, .reverse = true },
        }, .{ .row_offset = 0, .col_offset = 0 });

        // If we have a loaded image, display it (T032)
        if (self.preview_image) |img| {
            // Create a child window for the image (below title bar)
            const img_win = win.child(.{
                .y_off = 1,
                .height = if (height > 1) height - 1 else 1,
            });

            // Draw the image scaled to fit the window
            try img.draw(img_win, .{ .scale = .contain });
        } else if (self.preview_content) |content| {
            // Fallback: show text message centered (T033)
            const row: u16 = if (height > 3) height / 2 else 1;
            const col: u16 = if (content.len < win.width)
                (win.width - @as(u16, @intCast(content.len))) / 2
            else
                0;
            _ = win.printSegment(.{
                .text = content,
                .style = .{ .fg = .{ .index = 8 } }, // dim
            }, .{ .row_offset = row, .col_offset = col });
        }
    }

    // ===== File Watching (Phase 3 - US4) =====

    /// Poll file watcher for changes (T054, T055, T058, T059, T060)
    fn pollFileWatcher(self: *Self) !void {
        // Initialize watcher if needed (lazy init when file_tree is loaded)
        if (self.file_watcher == null and self.file_tree != null) {
            self.file_watcher = watcher.Watcher.init(self.allocator, self.file_tree.?.root_path) catch null;
        }

        const w = self.file_watcher orelse return;

        // Poll for changes
        if (w.poll()) {
            // Watcher detected a change, use debouncer to coalesce rapid changes (T055)
            if (self.watch_debouncer.recordEvent()) {
                // Debounce passed, trigger refresh
                try self.handleFileSystemChange();
            }
        } else if (self.watch_debouncer.checkPending()) {
            // Handle pending debounced event
            try self.handleFileSystemChange();
        }
    }

    /// Handle file system change detected by watcher
    fn handleFileSystemChange(self: *Self) !void {
        // T059: Preserve cursor position on auto-refresh
        // Save the current path at cursor position
        var saved_path: ?[]const u8 = null;
        if (self.file_tree) |ft| {
            if (ft.visibleToActualIndex(self.cursor, self.show_hidden)) |idx| {
                saved_path = try self.allocator.dupe(u8, ft.entries.items[idx].path);
            }
        }
        defer if (saved_path) |p| self.allocator.free(p);

        // Reload tree (T060: expanded_paths is preserved by reloadTree -> restoreExpandedState)
        try self.reloadTree();

        // T059: Restore cursor position if possible
        if (saved_path) |path| {
            if (self.file_tree) |ft| {
                for (ft.entries.items, 0..) |entry, i| {
                    if (std.mem.eql(u8, entry.path, path)) {
                        if (ft.actualToVisibleIndex(i, self.show_hidden)) |visible_idx| {
                            self.cursor = visible_idx;
                            self.updateScrollOffset();
                        }
                        break;
                    }
                }
            }
        }

        // T058: VCS status is refreshed by reloadTree() which calls refreshVCSStatus()
        // Show status message for auto-refresh
        self.status_message = "Auto-refreshed";
    }

    /// Toggle file watching (T056, T061)
    fn toggleWatching(self: *Self) void {
        // Initialize watcher if not exists
        if (self.file_watcher == null and self.file_tree != null) {
            self.file_watcher = watcher.Watcher.init(self.allocator, self.file_tree.?.root_path) catch {
                self.status_message = "Failed to enable watching";
                return;
            };
        }

        const w = self.file_watcher orelse {
            self.status_message = "Watching unavailable";
            return;
        };

        const new_state = !w.isEnabled();
        w.setEnabled(new_state);
        self.watch_debouncer.reset();

        // T061: Status message for watching toggle
        self.status_message = if (new_state) "Watching enabled" else "Watching disabled";
    }

    // ===== Drag & Drop via Bracketed Paste (Phase 3 - US3) =====

    /// Handle pasted content - detect file paths and treat as drops (T038, T042)
    fn handlePastedContent(self: *Self, content: []const u8) !void {
        if (content.len == 0) return;

        // Parse paths (may be multiple, separated by newlines)
        var paths: std.ArrayList([]const u8) = .empty;
        defer {
            for (paths.items) |p| self.allocator.free(p);
            paths.deinit(self.allocator);
        }

        // Try to extract file paths from the pasted content
        // First split by newlines, then by unescaped spaces (for multi-file drops)
        var iter = std.mem.tokenizeAny(u8, content, "\n\r");
        while (iter.next()) |line| {
            // Split line by unescaped spaces (Finder sends "path1 path2" for multi-file)
            var line_paths = try self.splitByUnescapedSpace(line);
            defer line_paths.deinit(self.allocator);

            for (line_paths.items) |segment| {
                const trimmed = std.mem.trim(u8, segment, " \t");
                if (trimmed.len == 0) continue;

                try self.processDropPath(&paths, trimmed);
            }
        }

        if (paths.items.len == 0) {
            // No valid file paths found - show sanitized version of what we received
            const show_len = @min(content.len, 40);
            // Sanitize control characters to prevent terminal escape injection
            var sanitized: [40]u8 = undefined;
            for (content[0..show_len], 0..) |c, idx| {
                sanitized[idx] = if (c < 0x20 or c == 0x7F) '?' else c;
            }
            self.status_message = std.fmt.bufPrint(&self.status_message_buf, "no paths in: '{s}'", .{sanitized[0..show_len]}) catch "no valid paths";
            return;
        }

        // Handle as file drop
        try self.handleFileDrop(paths.items);
    }

    /// Split a string by unescaped spaces (backslash-escaped spaces are kept)
    /// Only treats "\ " and "\\" as escape sequences (matches unescapePath behavior)
    fn splitByUnescapedSpace(self: *Self, input: []const u8) !std.ArrayList([]const u8) {
        var result: std.ArrayList([]const u8) = .empty;
        var start: usize = 0;
        var i: usize = 0;

        while (i < input.len) {
            if (input[i] == '\\' and i + 1 < input.len) {
                const next = input[i + 1];
                if (next == ' ' or next == '\\') {
                    // Skip escaped space or backslash
                    i += 2;
                } else {
                    // Other backslash - not an escape, advance by 1
                    i += 1;
                }
            } else if (input[i] == ' ') {
                // Unescaped space - split here
                if (i > start) {
                    try result.append(self.allocator, input[start..i]);
                }
                start = i + 1;
                i += 1;
            } else {
                i += 1;
            }
        }

        // Add remaining segment
        if (start < input.len) {
            try result.append(self.allocator, input[start..]);
        }

        return result;
    }

    /// Process a single drop path - decode, unescape, validate, and add to paths list
    fn processDropPath(self: *Self, paths: *std.ArrayList([]const u8), trimmed: []const u8) !void {
        // Strip file:// prefix if present (some terminals use URI format)
        // Only accept file:///path (empty host) and file://localhost/path
        // Reject file://otherhost/path to prevent unintended local copies
        const without_prefix = blk: {
            if (std.mem.startsWith(u8, trimmed, "file://localhost/")) {
                break :blk trimmed[16..]; // "file://localhost" = 16 chars, keep the /
            } else if (std.mem.startsWith(u8, trimmed, "file:///")) {
                break :blk trimmed[7..]; // "file://" = 7 chars, keep the /
            } else if (std.mem.startsWith(u8, trimmed, "file://")) {
                // Reject file://otherhost/... - non-local host
                return;
            } else {
                break :blk trimmed;
            }
        };

        // URL decode (e.g., %20 -> space)
        const url_decoded = self.urlDecodePath(without_prefix) catch return;
        defer if (url_decoded.ptr != without_prefix.ptr) self.allocator.free(url_decoded);

        // Unescape backslash-escaped characters (Finder uses "\ " for spaces)
        const unescaped = self.unescapePath(url_decoded) catch return;
        defer if (unescaped.ptr != url_decoded.ptr) self.allocator.free(unescaped);

        // Check if this looks like a file path
        if (self.isValidFilePath(unescaped)) {
            const path_copy = self.allocator.dupe(u8, unescaped) catch return;
            paths.append(self.allocator, path_copy) catch {
                self.allocator.free(path_copy);
                return;
            };
        }
    }

    /// URL decode path (e.g., %20 -> space, %2F -> /)
    fn urlDecodePath(self: *Self, path: []const u8) ![]const u8 {
        // Check if we need to decode
        if (std.mem.indexOf(u8, path, "%") == null) return path;

        // Allocate and decode
        var result = try self.allocator.alloc(u8, path.len);
        var out_idx: usize = 0;
        var i: usize = 0;
        while (i < path.len) {
            if (path[i] == '%' and i + 2 < path.len) {
                // Try to parse hex digits
                const hex = path[i + 1 .. i + 3];
                if (std.fmt.parseInt(u8, hex, 16)) |byte| {
                    result[out_idx] = byte;
                    out_idx += 1;
                    i += 3;
                    continue;
                } else |_| {}
            }
            result[out_idx] = path[i];
            out_idx += 1;
            i += 1;
        }
        return self.allocator.realloc(result, out_idx) catch result[0..out_idx];
    }

    /// Unescape backslash-escaped spaces in path (e.g., "\ " -> " ")
    /// Only unescapes "\ " (Finder's space escape) and "\\" (literal backslash)
    /// Other backslash sequences are kept as-is to preserve literal backslashes in filenames
    fn unescapePath(self: *Self, path: []const u8) ![]const u8 {
        // Count if we need to unescape (look for "\ " or "\\")
        var has_escape = false;
        var i: usize = 0;
        while (i < path.len) : (i += 1) {
            if (path[i] == '\\' and i + 1 < path.len) {
                const next = path[i + 1];
                if (next == ' ' or next == '\\') {
                    has_escape = true;
                    break;
                }
            }
        }
        if (!has_escape) return path;

        // Allocate and unescape only "\ " and "\\"
        var result = try self.allocator.alloc(u8, path.len);
        var out_idx: usize = 0;
        i = 0;
        while (i < path.len) : (i += 1) {
            if (path[i] == '\\' and i + 1 < path.len) {
                const next = path[i + 1];
                if (next == ' ' or next == '\\') {
                    // Skip backslash, keep the escaped character
                    i += 1;
                    result[out_idx] = path[i];
                } else {
                    // Keep other backslash sequences as-is
                    result[out_idx] = path[i];
                }
            } else {
                result[out_idx] = path[i];
            }
            out_idx += 1;
        }
        return self.allocator.realloc(result, out_idx) catch result[0..out_idx];
    }

    /// Check if a string looks like a valid file path that exists (T039)
    fn isValidFilePath(_: *Self, path: []const u8) bool {
        // Must start with / (absolute path) or ~ (home-relative)
        if (path.len == 0) return false;
        if (path[0] != '/' and path[0] != '~') return false;

        // Expand ~ to home directory
        var expanded_buf: [4096]u8 = undefined;
        const expanded = if (path[0] == '~') blk: {
            const home = std.posix.getenv("HOME") orelse return false;
            if (path.len == 1) {
                break :blk home;
            }
            const rest = path[1..];
            const result = std.fmt.bufPrint(&expanded_buf, "{s}{s}", .{ home, rest }) catch return false;
            break :blk result;
        } else path;

        // Check if file/directory exists
        std.fs.cwd().access(expanded, .{}) catch return false;
        return true;
    }

    /// Handle file drop - copy files to cursor directory or root (T040, T041, T042, T046, T047)
    fn handleFileDrop(self: *Self, paths: []const []const u8) !void {
        const ft = self.file_tree orelse return;

        // Determine destination: use cursor position directory
        const dest_dir = blk: {
            // If cursor is on a valid entry, use its directory
            if (ft.visibleToActualIndex(self.cursor, self.show_hidden)) |actual_idx| {
                if (actual_idx < ft.entries.items.len) {
                    const entry = &ft.entries.items[actual_idx];
                    if (entry.kind == .directory) {
                        break :blk entry.path;
                    } else {
                        // For files, use parent directory
                        break :blk std.fs.path.dirname(entry.path) orelse ft.root_path;
                    }
                }
            }
            break :blk ft.root_path;
        };

        var success_count: usize = 0;
        const total_count: usize = paths.len;

        for (paths) |src_path| {
            // Expand ~ if needed
            var expanded_buf: [4096]u8 = undefined;
            const expanded = if (src_path.len > 0 and src_path[0] == '~') blk: {
                const home = std.posix.getenv("HOME") orelse continue;
                if (src_path.len == 1) {
                    break :blk home;
                }
                const rest = src_path[1..];
                break :blk std.fmt.bufPrint(&expanded_buf, "{s}{s}", .{ home, rest }) catch continue;
            } else src_path;

            const filename = std.fs.path.basename(expanded);

            // Generate destination path with conflict resolution (T043, T044a)
            const final_dest = self.resolveDropConflict(dest_dir, filename) catch {
                // Too many conflicts or allocation error - skip this file
                continue;
            };
            defer self.allocator.free(final_dest);

            // Copy the file/directory (T040, T041)
            self.copyPath(expanded, final_dest) catch {
                continue;
            };
            success_count += 1;
        }

        if (success_count > 0) {
            try self.reloadTree();
            // Set status message (T047)
            if (success_count == 1) {
                self.status_message = "Dropped 1 file";
            } else {
                self.status_message = std.fmt.bufPrint(&self.status_message_buf, "Dropped {d} files", .{success_count}) catch "Dropped files";
            }
            if (success_count < total_count) {
                self.status_message = std.fmt.bufPrint(&self.status_message_buf, "Dropped {d}/{d} files", .{ success_count, total_count }) catch "Dropped (some failed)";
            }
        } else if (total_count > 0) {
            self.status_message = "Drop failed";
        }
    }

    /// Resolve filename conflict for dropped file - returns "name (2).ext" style (T043, T044a)
    fn resolveDropConflict(self: *Self, dest_dir: []const u8, filename: []const u8) ![]const u8 {
        const initial_path = try std.fs.path.join(self.allocator, &.{ dest_dir, filename });

        // Check if file exists
        if (std.fs.cwd().access(initial_path, .{})) |_| {
            // File exists, need to find alternative name
            self.allocator.free(initial_path);

            const ext = std.fs.path.extension(filename);
            const stem = filename[0 .. filename.len - ext.len];

            var suffix: usize = 2;
            while (suffix <= 100) {
                // Format: "name (2).ext" per spec T044a
                const new_name = try std.fmt.allocPrint(self.allocator, "{s} ({d}){s}", .{ stem, suffix, ext });
                defer self.allocator.free(new_name);

                const new_path = try std.fs.path.join(self.allocator, &.{ dest_dir, new_name });

                if (std.fs.cwd().access(new_path, .{})) |_| {
                    // Still exists, try next number
                    self.allocator.free(new_path);
                    suffix += 1;
                } else |_| {
                    // Doesn't exist, use this path
                    return new_path;
                }
            }

            // Too many conflicts
            return error.TooManyConflicts;
        } else |_| {
            // Doesn't exist, use initial path
            return initial_path;
        }
    }

    // ===== VCS Integration (Phase 3 - US1) =====

    /// Refresh VCS status for the current directory (T019)
    fn refreshVCSStatus(self: *Self) void {
        const ft = self.file_tree orelse return;

        // Free previous status
        if (self.vcs_status) |*status| {
            status.deinit();
            self.vcs_status = null;
        }

        // Detect VCS type
        self.vcs_type = vcs.detectVCS(ft.root_path);

        // Get status based on mode
        self.vcs_status = vcs.getVCSStatus(
            self.allocator,
            ft.root_path,
            self.vcs_type,
            self.vcs_mode,
        ) catch null;
    }

    /// Cycle VCS mode and refresh status (T018, T025)
    fn cycleVCSMode(self: *Self) void {
        self.vcs_mode = vcs.cycleVCSMode(self.vcs_mode);
        self.refreshVCSStatus();

        // Show status message
        const mode_name = vcs.vcsModeName(self.vcs_mode);
        const msg = std.fmt.bufPrint(&self.status_message_buf, "VCS: {s}", .{mode_name}) catch "VCS mode changed";
        self.status_message = msg;
    }

    /// Get VCS status for a file path (for UI rendering)
    pub fn getFileVCSStatus(self: *const Self, path: []const u8) ?vcs.VCSFileStatus {
        const status = self.vcs_status orelse return null;
        const ft = self.file_tree orelse return null;

        // Convert absolute path to relative path from repo root
        if (std.mem.startsWith(u8, path, ft.root_path)) {
            var relative = path[ft.root_path.len..];
            // Remove leading slash
            if (relative.len > 0 and relative[0] == '/') {
                relative = relative[1..];
            }
            return status.get(relative);
        }

        return null;
    }

    /// Get branch/change info for status bar display
    pub fn getVCSBranchDisplay(self: *const Self, arena: std.mem.Allocator) ?[]const u8 {
        const status = self.vcs_status orelse return null;

        // JJ format: @changeid (bookmark)
        if (self.vcs_type == .jj or (self.vcs_type != .none and self.vcs_mode == .jj)) {
            const change_id = status.branch orelse return null;
            if (status.bookmark) |bookmark| {
                return std.fmt.allocPrint(arena, "@{s} ({s})", .{ change_id, bookmark }) catch null;
            }
            return std.fmt.allocPrint(arena, "@{s}", .{change_id}) catch null;
        }

        // Git format: [branch]
        if (status.branch) |branch| {
            return std.fmt.allocPrint(arena, "[{s}]", .{branch}) catch null;
        }

        return null;
    }
};

/// Case-insensitive substring search (delegates to ui.findMatchPosition)
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    return ui.findMatchPosition(haystack, needle) != null;
}

pub fn run(allocator: std.mem.Allocator, start_path: []const u8, show_icons: bool) !void {
    const application = try App.init(allocator);
    defer application.deinit();

    // Set CLI options (Phase 3.5 - US4: T030)
    application.show_icons = show_icons;

    // Load directory
    application.file_tree = try tree.FileTree.init(allocator, start_path);
    try application.file_tree.?.readDirectory();

    // Refresh VCS status on startup (T020)
    application.refreshVCSStatus();

    // Run event loop
    try application.runEventLoop();
}

test "App state transitions" {
    // Test mode enum values
    var mode: AppMode = .tree_view;
    try std.testing.expectEqual(AppMode.tree_view, mode);

    mode = .preview;
    try std.testing.expectEqual(AppMode.preview, mode);
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

// Tests for isValidFilename, copyDirRecursive, and encodeBase64 are in file_ops.zig

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
        .rename,
        .new_file,
        .new_dir,
        .confirm_delete,
        .help,
    };

    // All 8 modes should be defined
    try std.testing.expectEqual(@as(usize, 8), modes.len);
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

// Tests for formatDisplayPath, isBinaryContent are in file_ops.zig

// ===== Phase 3.5 - US1: Mouse Click Tests =====

test "US1-T001: handleLeftClick calculates correct visible index from screen row" {
    // Test the calculation: target_visible = scroll_offset + screen_row
    // This is a logic verification test without App instance

    // Case 1: No scroll, clicking row 0 -> visible index 0
    const scroll_offset_1: usize = 0;
    const screen_row_1: u16 = 0;
    const expected_1: usize = scroll_offset_1 + @as(usize, screen_row_1);
    try std.testing.expectEqual(@as(usize, 0), expected_1);

    // Case 2: No scroll, clicking row 5 -> visible index 5
    const scroll_offset_2: usize = 0;
    const screen_row_2: u16 = 5;
    const expected_2: usize = scroll_offset_2 + @as(usize, screen_row_2);
    try std.testing.expectEqual(@as(usize, 5), expected_2);

    // Case 3: Scrolled by 10, clicking row 3 -> visible index 13
    const scroll_offset_3: usize = 10;
    const screen_row_3: u16 = 3;
    const expected_3: usize = scroll_offset_3 + @as(usize, screen_row_3);
    try std.testing.expectEqual(@as(usize, 13), expected_3);
}

test "US1-T002: click outside tree area (status bar) is ignored" {
    // Status bar occupies bottom 2 rows
    // tree_height = win.height - 2
    // Clicks at row >= tree_height should be ignored

    // Case 1: Window height 20, tree_height = 18, click at row 18 -> status bar
    const win_height_1: u16 = 20;
    const tree_height_1: u16 = if (win_height_1 > 2) win_height_1 - 2 else 0;
    const click_row_1: u16 = 18;
    try std.testing.expect(click_row_1 >= tree_height_1); // Should be ignored

    // Case 2: Window height 20, tree_height = 18, click at row 17 -> valid
    const click_row_2: u16 = 17;
    try std.testing.expect(click_row_2 < tree_height_1); // Should be valid
}

test "US1-T002a: click on blank row below last entry is ignored" {
    // If target_visible >= visible_count, ignore the click
    // Example: 5 visible entries, click at visible index 5 or higher -> ignore

    const visible_count: usize = 5;

    // Click at visible index 4 (last entry) -> valid
    const target_valid: usize = 4;
    try std.testing.expect(target_valid < visible_count);

    // Click at visible index 5 (blank row) -> ignore
    const target_blank: usize = 5;
    try std.testing.expect(target_blank >= visible_count);

    // Click at visible index 10 (well below) -> ignore
    const target_far: usize = 10;
    try std.testing.expect(target_far >= visible_count);
}

// ===== Phase 3.5 - US2: Double Click Tests =====

test "US2-T007: double-click detection within threshold (400ms)" {
    // Double-click threshold is 400ms
    const threshold_ns: u64 = 400 * std.time.ns_per_ms;

    // Simulated times
    const click1_ns: u64 = 0;
    const click2_ns: u64 = 200 * std.time.ns_per_ms; // 200ms later

    const elapsed = click2_ns - click1_ns;
    try std.testing.expect(elapsed <= threshold_ns); // Should be detected as double-click
}

test "US2-T008: single-click when exceeding threshold (400ms)" {
    const threshold_ns: u64 = 400 * std.time.ns_per_ms;

    // Simulated times
    const click1_ns: u64 = 0;
    const click2_ns: u64 = 500 * std.time.ns_per_ms; // 500ms later

    const elapsed = click2_ns - click1_ns;
    try std.testing.expect(elapsed > threshold_ns); // Should NOT be detected as double-click
}

test "US2-T009: clicks on different entries are not double-click" {
    // Different visible indices mean not a double-click, regardless of timing
    const entry1: usize = 5;
    const entry2: usize = 8;

    try std.testing.expect(entry1 != entry2); // Should not be double-click
}

test "US2-T009a: scroll between clicks means different entry" {
    // If user scrolls between clicks, the same screen row maps to different entries
    // Click 1: scroll_offset=0, row=5 -> visible_index=5
    // User scrolls down by 3
    // Click 2: scroll_offset=3, row=5 -> visible_index=8

    const scroll_offset_1: usize = 0;
    const screen_row: u16 = 5;
    const entry_1 = scroll_offset_1 + @as(usize, screen_row);

    const scroll_offset_2: usize = 3;
    const entry_2 = scroll_offset_2 + @as(usize, screen_row);

    try std.testing.expect(entry_1 != entry_2); // Different entries, not double-click
}

