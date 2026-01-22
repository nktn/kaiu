const std = @import("std");
const app = @import("app.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const raw_path = if (args.len > 1) args[1] else ".";

    // Expand ~ to home directory and validate path
    const start_path = expandAndValidatePath(allocator, raw_path) catch |err| {
        switch (err) {
            error.HomeNotFound => std.debug.print("Error: Cannot resolve home directory\n", .{}),
            error.PathNotFound => std.debug.print("Error: Path not found: {s}\n", .{raw_path}),
            error.NotADirectory => std.debug.print("Error: Not a directory: {s}\n", .{raw_path}),
            error.AccessDenied => std.debug.print("Error: Permission denied: {s}\n", .{raw_path}),
            else => std.debug.print("Error: Cannot access path: {s}\n", .{raw_path}),
        }
        std.process.exit(1);
    };
    defer if (start_path.ptr != raw_path.ptr) allocator.free(start_path);

    try app.run(allocator, start_path);
}

/// Expand ~ to home directory and validate path exists and is a directory.
/// Returns the expanded path (caller owns if different from input).
pub fn expandAndValidatePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var resolved_path: []const u8 = path;
    var needs_free = false;

    // Expand ~ to home directory
    if (path.len > 0 and path[0] == '~') {
        const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        if (path.len == 1) {
            // Just "~"
            resolved_path = home;
        } else if (path.len > 1 and path[1] == '/') {
            // "~/something"
            resolved_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] });
            needs_free = true;
        } else {
            // "~username" - not supported, treat as literal
            resolved_path = path;
        }
    }
    errdefer if (needs_free) allocator.free(resolved_path);

    // Validate path exists and is a directory
    const stat = std.fs.cwd().statFile(resolved_path) catch |err| {
        if (needs_free) allocator.free(resolved_path);
        return switch (err) {
            error.FileNotFound => error.PathNotFound,
            error.AccessDenied => error.AccessDenied,
            else => error.PathNotFound,
        };
    };

    if (stat.kind != .directory) {
        if (needs_free) allocator.free(resolved_path);
        return error.NotADirectory;
    }

    return resolved_path;
}

test "main imports" {
    _ = @import("app.zig");
    _ = @import("tree.zig");
    _ = @import("ui.zig");
}

test "expandAndValidatePath with current directory" {
    const allocator = std.testing.allocator;
    const result = try expandAndValidatePath(allocator, ".");
    // "." should be returned as-is (no allocation)
    try std.testing.expectEqualStrings(".", result);
}

test "expandAndValidatePath with non-existent path" {
    const allocator = std.testing.allocator;
    const result = expandAndValidatePath(allocator, "/nonexistent/path/12345");
    try std.testing.expectError(error.PathNotFound, result);
}

test "expandAndValidatePath with file instead of directory" {
    const allocator = std.testing.allocator;

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("testfile.txt", .{});
    file.close();

    const path = try tmp_dir.dir.realpathAlloc(allocator, "testfile.txt");
    defer allocator.free(path);

    const result = expandAndValidatePath(allocator, path);
    try std.testing.expectError(error.NotADirectory, result);
}

test "expandAndValidatePath with tilde expansion" {
    const allocator = std.testing.allocator;

    // Only test if HOME is set
    if (std.posix.getenv("HOME")) |home| {
        // Test "~" alone
        const result = try expandAndValidatePath(allocator, "~");
        try std.testing.expectEqualStrings(home, result);
        // No free needed - returned home directly

        // Test "~/." (home directory with dot)
        const result2 = try expandAndValidatePath(allocator, "~/.");
        defer allocator.free(result2);
        try std.testing.expect(std.mem.startsWith(u8, result2, home));
    }
}
