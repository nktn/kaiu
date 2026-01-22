const std = @import("std");

pub const EntryKind = enum {
    file,
    directory,
};

pub const FileEntry = struct {
    name: []const u8,
    path: []const u8,
    kind: EntryKind,
    is_hidden: bool,
    expanded: bool,
    children: ?std.ArrayList(FileEntry),
    depth: usize,

    pub fn isDir(self: FileEntry) bool {
        return self.kind == .directory;
    }

    pub fn deinit(self: *FileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        if (self.children) |*children| {
            for (children.items) |*child| {
                child.deinit(allocator);
            }
            children.deinit(allocator);
        }
    }
};

pub const FileTree = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    root_path: []const u8,
    entries: std.ArrayList(FileEntry),

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*FileTree {
        const self = try allocator.create(FileTree);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root_path = try allocator.dupe(u8, path),
            .entries = .empty,
        };

        return self;
    }

    pub fn deinit(self: *FileTree) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
        self.allocator.free(self.root_path);
        self.arena.deinit();
        self.allocator.destroy(self);
    }

    pub fn readDirectory(self: *FileTree) !void {
        try self.readDirectoryRecursive(self.root_path, 0, &self.entries);
    }

    fn readDirectoryRecursive(
        self: *FileTree,
        path: []const u8,
        depth: usize,
        entries: *std.ArrayList(FileEntry),
    ) !void {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.AccessDenied => return,
                else => return err,
            }
        };
        defer dir.close();

        var iter = dir.iterate();
        var temp_entries: std.ArrayList(FileEntry) = .empty;
        defer temp_entries.deinit(self.allocator);
        errdefer {
            // Clean up allocated strings in temp_entries on error
            for (temp_entries.items) |*e| {
                self.allocator.free(e.name);
                self.allocator.free(e.path);
            }
        }

        while (try iter.next()) |entry| {
            const name = try self.allocator.dupe(u8, entry.name);
            errdefer self.allocator.free(name);

            const full_path = try std.fs.path.join(self.allocator, &.{ path, entry.name });
            errdefer self.allocator.free(full_path);

            const is_hidden = entry.name.len > 0 and entry.name[0] == '.';
            const kind: EntryKind = if (entry.kind == .directory) .directory else .file;

            try temp_entries.append(self.allocator, .{
                .name = name,
                .path = full_path,
                .kind = kind,
                .is_hidden = is_hidden,
                .expanded = false,
                .children = null,
                .depth = depth,
            });
        }

        // Sort: directories first, then alphabetically
        std.mem.sort(FileEntry, temp_entries.items, {}, struct {
            fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
                // Directories come first
                if (a.kind != b.kind) {
                    return a.kind == .directory;
                }
                // Then sort alphabetically (case-insensitive)
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);

        // Move sorted entries to the target list
        try entries.appendSlice(self.allocator, temp_entries.items);
        temp_entries.clearRetainingCapacity();
    }

    pub fn toggleExpand(self: *FileTree, index: usize) !void {
        if (index >= self.entries.items.len) return;

        const entry = &self.entries.items[index];
        if (entry.kind != .directory) return;

        if (entry.expanded) {
            // Collapse: remove children from flat list
            self.collapseAt(index);
        } else {
            // Expand: read children and insert into flat list
            try self.expandAt(index);
        }
    }

    fn expandAt(self: *FileTree, index: usize) !void {
        const entry = &self.entries.items[index];
        if (entry.kind != .directory or entry.expanded) return;

        var new_entries: std.ArrayList(FileEntry) = .empty;
        defer new_entries.deinit(self.allocator);

        try self.readDirectoryRecursive(entry.path, entry.depth + 1, &new_entries);

        // Insert new entries after current index
        const insert_pos = index + 1;
        try self.entries.insertSlice(self.allocator, insert_pos, new_entries.items);
        new_entries.clearRetainingCapacity();

        // Re-fetch after potential realloc and mark as expanded
        self.entries.items[index].expanded = true;
    }

    pub fn collapseAt(self: *FileTree, index: usize) void {
        const entry = &self.entries.items[index];
        if (entry.kind != .directory or !entry.expanded) return;

        const parent_depth = entry.depth;
        var remove_count: usize = 0;

        // Count how many entries to remove (all descendants)
        var i = index + 1;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].depth <= parent_depth) break;
            // Free the entry's allocated strings
            const child = &self.entries.items[i];
            self.allocator.free(child.name);
            self.allocator.free(child.path);
            remove_count += 1;
            i += 1;
        }

        // Remove entries
        if (remove_count > 0) {
            const start = index + 1;
            std.mem.copyForwards(
                FileEntry,
                self.entries.items[start..],
                self.entries.items[start + remove_count ..],
            );
            self.entries.shrinkRetainingCapacity(self.entries.items.len - remove_count);
        }

        // Re-fetch after modification and mark as collapsed
        self.entries.items[index].expanded = false;
    }

    pub fn countVisible(self: *FileTree, show_hidden: bool) usize {
        if (show_hidden) {
            return self.entries.items.len;
        }
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if (!entry.is_hidden) count += 1;
        }
        return count;
    }

    /// Convert visible index to actual entries index.
    /// Returns null if visible_index is out of range.
    pub fn visibleToActualIndex(self: *FileTree, visible_index: usize, show_hidden: bool) ?usize {
        if (show_hidden) {
            if (visible_index >= self.entries.items.len) return null;
            return visible_index;
        }

        var visible_count: usize = 0;
        for (self.entries.items, 0..) |entry, actual_index| {
            if (!entry.is_hidden) {
                if (visible_count == visible_index) {
                    return actual_index;
                }
                visible_count += 1;
            }
        }
        return null;
    }
};

test "FileTree init and deinit" {
    const allocator = std.testing.allocator;
    const ft = try FileTree.init(allocator, "/tmp");
    defer ft.deinit();

    try std.testing.expectEqualStrings("/tmp", ft.root_path);
}

test "FileEntry isDir" {
    const dir_entry = FileEntry{
        .name = "test",
        .path = "/test",
        .kind = .directory,
        .is_hidden = false,
        .expanded = false,
        .children = null,
        .depth = 0,
    };
    try std.testing.expect(dir_entry.isDir());

    const file_entry = FileEntry{
        .name = "test.txt",
        .path = "/test.txt",
        .kind = .file,
        .is_hidden = false,
        .expanded = false,
        .children = null,
        .depth = 0,
    };
    try std.testing.expect(!file_entry.isDir());
}

test "FileTree readDirectory" {
    const allocator = std.testing.allocator;

    // Create a test directory structure
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files and directories
    try tmp_dir.dir.makeDir("subdir");
    var file = try tmp_dir.dir.createFile("file.txt", .{});
    file.close();
    var hidden = try tmp_dir.dir.createFile(".hidden", .{});
    hidden.close();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const ft = try FileTree.init(allocator, path);
    defer ft.deinit();

    try ft.readDirectory();

    // Should have 3 entries: subdir, file.txt, .hidden
    try std.testing.expectEqual(@as(usize, 3), ft.entries.items.len);

    // First should be directory (sorted first)
    try std.testing.expectEqual(EntryKind.directory, ft.entries.items[0].kind);
    try std.testing.expectEqualStrings("subdir", ft.entries.items[0].name);
}

test "FileTree hidden file detection" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var hidden = try tmp_dir.dir.createFile(".hidden", .{});
    hidden.close();
    var visible = try tmp_dir.dir.createFile("visible.txt", .{});
    visible.close();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const ft = try FileTree.init(allocator, path);
    defer ft.deinit();

    try ft.readDirectory();

    var hidden_count: usize = 0;
    for (ft.entries.items) |entry| {
        if (entry.is_hidden) hidden_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 1), hidden_count);
}

test "FileTree visibleToActualIndex" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files: .hidden (index 0), visible1.txt (index 1), visible2.txt (index 2)
    var hidden = try tmp_dir.dir.createFile(".hidden", .{});
    hidden.close();
    var visible1 = try tmp_dir.dir.createFile("visible1.txt", .{});
    visible1.close();
    var visible2 = try tmp_dir.dir.createFile("visible2.txt", .{});
    visible2.close();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const ft = try FileTree.init(allocator, path);
    defer ft.deinit();

    try ft.readDirectory();

    // With show_hidden=true, visible index == actual index
    try std.testing.expectEqual(@as(?usize, 0), ft.visibleToActualIndex(0, true));
    try std.testing.expectEqual(@as(?usize, 1), ft.visibleToActualIndex(1, true));
    try std.testing.expectEqual(@as(?usize, 2), ft.visibleToActualIndex(2, true));
    try std.testing.expectEqual(@as(?usize, null), ft.visibleToActualIndex(3, true));

    // With show_hidden=false, visible index skips hidden files
    // Sorted order: .hidden (hidden), visible1.txt, visible2.txt
    // visible index 0 -> actual index 1 (visible1.txt)
    // visible index 1 -> actual index 2 (visible2.txt)
    try std.testing.expectEqual(@as(?usize, 1), ft.visibleToActualIndex(0, false));
    try std.testing.expectEqual(@as(?usize, 2), ft.visibleToActualIndex(1, false));
    try std.testing.expectEqual(@as(?usize, null), ft.visibleToActualIndex(2, false));
}
