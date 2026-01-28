const std = @import("std");
const app = @import("app.zig");

// Include icons module for testing (T032)
pub const icons = @import("icons.zig");

/// Result of path expansion and validation.
pub const PathResult = struct {
    path: []const u8,
    owned: bool,
};

/// CLI options parsed from command line arguments (Phase 3.5 - US4: T029)
pub const CliOptions = struct {
    path: []const u8,
    show_icons: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Parse command line arguments (T029)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli_options = parseCliArgs(args);

    // Expand ~ to home directory and validate path
    const result = expandAndValidatePath(allocator, cli_options.path) catch |err| {
        switch (err) {
            error.HomeNotFound => std.debug.print("Error: Cannot resolve home directory\n", .{}),
            error.PathNotFound => std.debug.print("Error: Path not found: {s}\n", .{cli_options.path}),
            error.NotADirectory => std.debug.print("Error: Not a directory: {s}\n", .{cli_options.path}),
            error.AccessDenied => std.debug.print("Error: Permission denied: {s}\n", .{cli_options.path}),
            else => std.debug.print("Error: Cannot access path: {s}\n", .{cli_options.path}),
        }
        std.process.exit(1);
    };
    defer if (result.owned) allocator.free(result.path);

    try app.run(allocator, result.path, cli_options.show_icons);
}

/// Parse CLI arguments (Phase 3.5 - US4: T029)
/// FR-033: --no-icons flag to disable icon display
fn parseCliArgs(args: []const [:0]const u8) CliOptions {
    var show_icons: bool = true;
    var path_arg: []const u8 = ".";

    // Skip argv[0] (program name)
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--no-icons")) {
            show_icons = false;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // Non-flag argument is the path
            path_arg = arg;
        }
    }

    return .{
        .path = path_arg,
        .show_icons = show_icons,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: kaiu [OPTIONS] [PATH]
        \\
        \\Arguments:
        \\  PATH              Directory to explore (default: current directory)
        \\
        \\Options:
        \\  --no-icons        Disable Nerd Font icons
        \\  -h, --help        Show this help message
        \\
    , .{});
}

/// Expand ~ to home directory and validate path exists and is a directory.
/// Returns PathResult with ownership flag - caller must free path if owned=true.
/// The returned path is always an absolute path (FR-030).
pub fn expandAndValidatePath(allocator: std.mem.Allocator, path: []const u8) !PathResult {
    var resolved_path: []const u8 = path;
    var owned = false;

    // Expand ~ to home directory
    if (path.len > 0 and path[0] == '~') {
        const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        if (path.len == 1) {
            // Just "~" - use home directory
            resolved_path = home;
            owned = false;
        } else if (path.len > 1 and path[1] == '/') {
            // "~/something" - allocate new path
            resolved_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] });
            owned = true;
        } else {
            // "~username" - not supported, treat as literal
            resolved_path = path;
            owned = false;
        }
    }
    errdefer if (owned) allocator.free(resolved_path);

    // Validate path exists and is a directory
    const stat = std.fs.cwd().statFile(resolved_path) catch |err| {
        return switch (err) {
            error.FileNotFound => error.PathNotFound,
            error.AccessDenied => error.AccessDenied,
            else => error.PathNotFound,
        };
    };

    if (stat.kind != .directory) {
        return error.NotADirectory;
    }

    // Convert to absolute path using realpathAlloc (FR-030)
    const abs_path = std.fs.cwd().realpathAlloc(allocator, resolved_path) catch |err| {
        return switch (err) {
            error.FileNotFound => error.PathNotFound,
            error.AccessDenied => error.AccessDenied,
            else => error.PathNotFound,
        };
    };
    // If we had a previously owned path from tilde expansion, free it
    if (owned) {
        allocator.free(resolved_path);
    }

    return .{ .path = abs_path, .owned = true };
}

test "main imports" {
    _ = @import("app.zig");
    _ = @import("tree.zig");
    _ = @import("ui.zig");
}

test "expandAndValidatePath with current directory" {
    const allocator = std.testing.allocator;
    const result = try expandAndValidatePath(allocator, ".");
    defer if (result.owned) allocator.free(result.path);

    // "." should be resolved to absolute path (FR-030)
    try std.testing.expect(result.path.len > 0);
    try std.testing.expect(result.path[0] == '/');
    try std.testing.expect(result.owned);
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
        defer if (result.owned) allocator.free(result.path);
        // Result should be absolute path (home directory)
        try std.testing.expectEqualStrings(home, result.path);

        // Test "~/." (home directory with dot)
        const result2 = try expandAndValidatePath(allocator, "~/.");
        defer if (result2.owned) allocator.free(result2.path);
        try std.testing.expect(std.mem.startsWith(u8, result2.path, home));
        try std.testing.expect(result2.owned); // allocated, owned
    }
}

test "expandAndValidatePath returns absolute path for relative paths" {
    const allocator = std.testing.allocator;

    // Create a temp directory and test relative path
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Get the absolute path of the temp dir
    const abs_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    // Validate that expandAndValidatePath with absolute path returns absolute
    const result = try expandAndValidatePath(allocator, abs_path);
    defer if (result.owned) allocator.free(result.path);

    try std.testing.expect(result.path[0] == '/');
    try std.testing.expectEqualStrings(abs_path, result.path);
}
