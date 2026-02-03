const std = @import("std");
const lsp = @import("lsp.zig");

/// Symbol reference with context for display in reference list.
pub const SymbolReference = struct {
    file_path: []const u8,
    line: u32,
    column: u32,
    snippet: []const u8,
    context_before: []const u8,
    context_after: []const u8,

    /// Free all owned memory.
    pub fn deinit(self: *SymbolReference, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.snippet);
        allocator.free(self.context_before);
        allocator.free(self.context_after);
    }
};

/// List of symbol references with filtering support.
pub const ReferenceList = struct {
    allocator: std.mem.Allocator,
    symbol_name: []const u8,
    references: std.ArrayList(SymbolReference),
    filtered: std.ArrayList(usize),
    filter_pattern: ?[]const u8,
    cursor: usize,
    scroll_offset: usize,

    pub fn init(allocator: std.mem.Allocator, symbol_name: []const u8) !ReferenceList {
        const name_copy = try allocator.dupe(u8, symbol_name);
        errdefer allocator.free(name_copy);

        return .{
            .allocator = allocator,
            .symbol_name = name_copy,
            .references = .empty,
            .filtered = .empty,
            .filter_pattern = null,
            .cursor = 0,
            .scroll_offset = 0,
        };
    }

    pub fn deinit(self: *ReferenceList) void {
        for (self.references.items) |*ref| {
            ref.deinit(self.allocator);
        }
        self.references.deinit(self.allocator);
        self.filtered.deinit(self.allocator);
        if (self.filter_pattern) |pattern| {
            self.allocator.free(pattern);
        }
        self.allocator.free(self.symbol_name);
    }

    /// Add a reference to the list.
    pub fn addReference(self: *ReferenceList, ref: SymbolReference) !void {
        try self.references.append(self.allocator, ref);
        // If no filter, add to filtered list
        if (self.filter_pattern == null) {
            try self.filtered.append(self.allocator, self.references.items.len - 1);
        }
    }

    /// Apply glob filter to file paths.
    pub fn applyFilter(self: *ReferenceList, pattern: []const u8) !void {
        // Clear old filter
        if (self.filter_pattern) |old| {
            self.allocator.free(old);
        }

        self.filter_pattern = try self.allocator.dupe(u8, pattern);
        self.filtered.clearRetainingCapacity();

        // T035: Glob pattern matching with * and ** wildcards
        for (self.references.items, 0..) |ref, i| {
            if (self.matchesFilter(ref.file_path, pattern)) {
                try self.filtered.append(self.allocator, i);
            }
        }

        // Reset cursor if out of bounds
        if (self.cursor >= self.filtered.items.len) {
            self.cursor = if (self.filtered.items.len > 0) self.filtered.items.len - 1 else 0;
        }
    }

    /// Clear filter and show all references.
    pub fn clearFilter(self: *ReferenceList) void {
        if (self.filter_pattern) |pattern| {
            self.allocator.free(pattern);
            self.filter_pattern = null;
        }

        self.filtered.clearRetainingCapacity();
        for (0..self.references.items.len) |i| {
            self.filtered.append(self.allocator, i) catch {};
        }
    }

    /// Get number of visible (filtered) references.
    pub fn visibleCount(self: *const ReferenceList) usize {
        return self.filtered.items.len;
    }

    /// Get reference at visible index.
    pub fn getVisible(self: *const ReferenceList, visible_index: usize) ?*const SymbolReference {
        if (visible_index >= self.filtered.items.len) return null;
        const actual_index = self.filtered.items[visible_index];
        return &self.references.items[actual_index];
    }

    /// Get currently selected reference.
    pub fn getCurrent(self: *const ReferenceList) ?*const SymbolReference {
        return self.getVisible(self.cursor);
    }

    /// Move cursor down.
    pub fn moveDown(self: *ReferenceList) void {
        if (self.cursor + 1 < self.filtered.items.len) {
            self.cursor += 1;
        }
    }

    /// Move cursor up.
    pub fn moveUp(self: *ReferenceList) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    fn matchesFilter(self: *const ReferenceList, path: []const u8, pattern: []const u8) bool {
        _ = self;
        // Handle exclude patterns (prefix with !)
        if (pattern.len > 0 and pattern[0] == '!') {
            const exclude_pattern = pattern[1..];
            // Return true if path does NOT match exclude pattern
            return !globMatch(path, exclude_pattern);
        }

        return globMatch(path, pattern);
    }

    /// Simple glob pattern matching supporting * and ** wildcards.
    fn globMatch(text: []const u8, pattern: []const u8) bool {
        var ti: usize = 0;
        var pi: usize = 0;
        var star_pi: ?usize = null;
        var star_ti: usize = 0;

        while (ti < text.len) {
            if (pi < pattern.len) {
                // Handle ** (match any path segment)
                if (pi + 1 < pattern.len and pattern[pi] == '*' and pattern[pi + 1] == '*') {
                    // ** matches everything including /
                    star_pi = pi;
                    star_ti = ti;
                    pi += 2;
                    // Skip trailing / after **
                    if (pi < pattern.len and pattern[pi] == '/') {
                        pi += 1;
                    }
                    continue;
                }
                // Handle single * (match within segment)
                if (pattern[pi] == '*') {
                    star_pi = pi;
                    star_ti = ti;
                    pi += 1;
                    continue;
                }
                // Character match
                if (pattern[pi] == text[ti]) {
                    ti += 1;
                    pi += 1;
                    continue;
                }
            }

            // Backtrack to last * if possible
            if (star_pi) |sp| {
                // For single *, don't match /
                if (sp + 1 < pattern.len and pattern[sp] == '*' and pattern[sp + 1] != '*') {
                    if (text[star_ti] == '/') {
                        return false;
                    }
                }
                star_ti += 1;
                ti = star_ti;
                pi = sp + 1;
                // Skip ** pattern
                if (pi < pattern.len and pattern[pi] == '*') {
                    pi += 1;
                    if (pi < pattern.len and pattern[pi] == '/') {
                        pi += 1;
                    }
                }
            } else {
                return false;
            }
        }

        // Skip trailing *'s
        while (pi < pattern.len and pattern[pi] == '*') {
            pi += 1;
        }

        return pi == pattern.len;
    }
};

test "ReferenceList init and deinit" {
    const allocator = std.testing.allocator;
    var list = try ReferenceList.init(allocator, "testSymbol");
    defer list.deinit();

    try std.testing.expectEqualStrings("testSymbol", list.symbol_name);
    try std.testing.expectEqual(@as(usize, 0), list.visibleCount());
    try std.testing.expect(list.filter_pattern == null);
}

test "ReferenceList cursor movement" {
    const allocator = std.testing.allocator;
    var list = try ReferenceList.init(allocator, "test");
    defer list.deinit();

    // Add some mock references
    for (0..3) |i| {
        const path = try std.fmt.allocPrint(allocator, "test{d}.zig", .{i});
        try list.addReference(.{
            .file_path = path,
            .line = @intCast(i + 1),
            .column = 1,
            .snippet = try allocator.dupe(u8, ""),
            .context_before = try allocator.dupe(u8, ""),
            .context_after = try allocator.dupe(u8, ""),
        });
    }

    try std.testing.expectEqual(@as(usize, 3), list.visibleCount());
    try std.testing.expectEqual(@as(usize, 0), list.cursor);

    list.moveDown();
    try std.testing.expectEqual(@as(usize, 1), list.cursor);

    list.moveDown();
    try std.testing.expectEqual(@as(usize, 2), list.cursor);

    list.moveDown(); // Should not go past end
    try std.testing.expectEqual(@as(usize, 2), list.cursor);

    list.moveUp();
    try std.testing.expectEqual(@as(usize, 1), list.cursor);

    list.moveUp();
    try std.testing.expectEqual(@as(usize, 0), list.cursor);

    list.moveUp(); // Should not go below 0
    try std.testing.expectEqual(@as(usize, 0), list.cursor);
}

test "globMatch basic patterns" {
    // Exact match
    try std.testing.expect(ReferenceList.globMatch("foo.zig", "foo.zig"));
    try std.testing.expect(!ReferenceList.globMatch("foo.zig", "bar.zig"));

    // Single * wildcard
    try std.testing.expect(ReferenceList.globMatch("foo.zig", "*.zig"));
    try std.testing.expect(ReferenceList.globMatch("bar.zig", "*.zig"));
    try std.testing.expect(!ReferenceList.globMatch("foo.txt", "*.zig"));

    // * in middle
    try std.testing.expect(ReferenceList.globMatch("test_foo_bar.zig", "test_*_bar.zig"));
    try std.testing.expect(ReferenceList.globMatch("test_x_bar.zig", "test_*_bar.zig"));
}

test "globMatch ** patterns" {
    // ** matches multiple segments
    try std.testing.expect(ReferenceList.globMatch("src/foo/bar.zig", "src/**"));
    try std.testing.expect(ReferenceList.globMatch("src/a/b/c.zig", "src/**"));
    try std.testing.expect(ReferenceList.globMatch("src/main.zig", "src/**"));

    // ** in middle
    try std.testing.expect(ReferenceList.globMatch("src/foo/bar.zig", "**/bar.zig"));
    try std.testing.expect(ReferenceList.globMatch("a/b/c/bar.zig", "**/bar.zig"));
}

test "ReferenceList filter with glob" {
    const allocator = std.testing.allocator;
    var list = try ReferenceList.init(allocator, "test");
    defer list.deinit();

    // Add references with different paths
    const paths = [_][]const u8{
        "src/main.zig",
        "src/utils/helper.zig",
        "tests/test_main.zig",
        "lib/external.zig",
    };

    for (paths) |path| {
        try list.addReference(.{
            .file_path = try allocator.dupe(u8, path),
            .line = 1,
            .column = 1,
            .snippet = try allocator.dupe(u8, ""),
            .context_before = try allocator.dupe(u8, ""),
            .context_after = try allocator.dupe(u8, ""),
        });
    }

    try std.testing.expectEqual(@as(usize, 4), list.visibleCount());

    // Filter: src/**
    try list.applyFilter("src/**");
    try std.testing.expectEqual(@as(usize, 2), list.visibleCount());

    // Clear filter
    list.clearFilter();
    try std.testing.expectEqual(@as(usize, 4), list.visibleCount());

    // Exclude filter: !tests/** (exclude tests directory)
    try list.applyFilter("!tests/**");
    try std.testing.expectEqual(@as(usize, 3), list.visibleCount());
}
