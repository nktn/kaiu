const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const ui = @import("ui.zig");

pub const AppMode = enum {
    tree_view,
    preview,
};

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    file_tree: ?*tree.FileTree,
    mode: AppMode,
    cursor: usize,
    scroll_offset: usize,
    show_hidden: bool,
    preview_content: ?[]const u8,
    preview_path: ?[]const u8,
    preview_scroll: usize,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    loop: vaxis.Loop(Event),
    tty_buf: [4096]u8,

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
            .preview_content = null,
            .preview_path = null,
            .preview_scroll = 0,
            .should_quit = false,
            .tty = undefined,
            .vx = undefined,
            .loop = undefined,
            .tty_buf = undefined,
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
        self.allocator.destroy(self);
    }

    pub fn runEventLoop(self: *Self) !void {
        const writer = self.tty.writer();

        // Enter alt screen
        try self.vx.enterAltScreen(writer);
        self.vx.queueRefresh();

        // Start the input thread
        try self.loop.start();

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

        switch (self.mode) {
            .tree_view => {
                switch (key_char) {
                    'q' => self.should_quit = true,
                    'j' => self.moveCursor(1),
                    'k' => self.moveCursor(-1),
                    'l', 'o', vaxis.Key.enter => try self.handleEnter(),
                    'h' => self.handleBack(),
                    'a' => self.toggleHidden(),
                    else => {},
                }
            },
            .preview => {
                switch (key_char) {
                    'q' => self.should_quit = true,
                    'h' => self.closePreview(),
                    'j' => self.preview_scroll +|= 1,
                    'k' => if (self.preview_scroll > 0) {
                        self.preview_scroll -= 1;
                    },
                    else => {},
                }
            },
        }
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

    fn handleEnter(self: *Self) !void {
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

    fn handleBack(self: *Self) void {
        if (self.file_tree == null) return;
        const ft = self.file_tree.?;

        const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;

        const entry = &ft.entries.items[actual_index];
        if (entry.kind == .directory and entry.expanded) {
            ft.collapseAt(actual_index);
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
                self.mode = .preview;
                return;
            };
            if (stat.size > max_size) {
                self.preview_content = try self.allocator.dupe(u8, "[File too large]");
                self.preview_path = try self.allocator.dupe(u8, path);
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
                self.mode = .preview;
                return;
            };
            var buf: [64]u8 = undefined;
            const size_str = std.fmt.bufPrint(&buf, "[Binary file - {d} bytes]", .{stat.size}) catch "[Binary file]";
            self.preview_content = try self.allocator.dupe(u8, size_str);
            self.preview_path = try self.allocator.dupe(u8, path);
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

    fn render(self: *Self, writer: anytype) !void {
        const win = self.vx.window();
        win.clear();

        switch (self.mode) {
            .tree_view => {
                if (self.file_tree) |ft| {
                    try ui.renderTree(win, ft, self.cursor, self.scroll_offset, self.show_hidden);
                } else {
                    _ = win.printSegment(.{ .text = "No directory loaded" }, .{});
                }
            },
            .preview => {
                // Full screen preview (simpler, avoids child window issues)
                if (self.preview_content) |content| {
                    const filename = if (self.preview_path) |p| std.fs.path.basename(p) else "preview";
                    try ui.renderPreview(win, content, filename, self.preview_scroll);
                }
            },
        }

        try self.vx.render(writer);
    }
};

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
