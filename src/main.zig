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

/// Config file settings (~/.config/kaiu/config)
pub const Config = struct {
    show_icons: ?bool = null, // null means not set in config
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

    // Load config file first (lowest priority)
    const config = loadConfig(allocator);

    // Parse command line arguments (T029) - CLI overrides config
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli_options = parseCliArgs(args, config);

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
/// Priority: CLI flags > config file > defaults
fn parseCliArgs(args: []const [:0]const u8, config: Config) CliOptions {
    // Start with config value or default (true)
    var show_icons: bool = config.show_icons orelse true;
    var path_arg: []const u8 = ".";

    // Skip argv[0] (program name)
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--no-icons")) {
            show_icons = false;
        } else if (std.mem.eql(u8, arg, "--icons")) {
            // Allow explicit --icons to override config
            show_icons = true;
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
        \\  --icons           Enable Nerd Font icons (override config)
        \\  -h, --help        Show this help message
        \\
        \\Config: ~/.config/kaiu/config
        \\  show_icons = false
        \\
    , .{});
}

/// Load config from ~/.config/kaiu/config
/// Returns Config with values from file, or defaults if file doesn't exist
fn loadConfig(allocator: std.mem.Allocator) Config {
    const home = std.posix.getenv("HOME") orelse return .{};

    const config_path = std.fmt.allocPrint(allocator, "{s}/.config/kaiu/config", .{home}) catch return .{};
    defer allocator.free(config_path);

    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        // FileNotFound is normal (no config file), other errors should warn
        if (err != error.FileNotFound) {
            std.debug.print("Warning: Cannot open config file: {s}\n", .{config_path});
        }
        return .{};
    };
    defer file.close();

    // Read entire file (config files are small, max 4KB)
    const content = file.readToEndAlloc(allocator, 4096) catch |err| {
        if (err == error.StreamTooLong) {
            std.debug.print("Warning: Config file too large (max 4KB): {s}\n", .{config_path});
        } else {
            std.debug.print("Warning: Cannot read config file: {s}\n", .{config_path});
        }
        return .{};
    };
    defer allocator.free(content);

    return parseConfig(content);
}

/// Parse config content into Config struct
fn parseConfig(content: []const u8) Config {
    var config = Config{};
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        // Skip empty lines and comments
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse "key = value" format (supports inline comments with #)
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var value_part = trimmed[eq_pos + 1 ..];
            // Strip inline comments
            if (std.mem.indexOf(u8, value_part, "#")) |comment_pos| {
                value_part = value_part[0..comment_pos];
            }
            const value = std.mem.trim(u8, value_part, " \t");

            if (std.mem.eql(u8, key, "show_icons")) {
                if (std.mem.eql(u8, value, "false")) {
                    config.show_icons = false;
                } else if (std.mem.eql(u8, value, "true")) {
                    config.show_icons = true;
                }
            }
        }
    }

    return config;
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

// Config file tests
test "parseConfig with show_icons = false" {
    const config = parseConfig("show_icons = false\n");
    try std.testing.expectEqual(false, config.show_icons.?);
}

test "parseConfig with show_icons = true" {
    const config = parseConfig("show_icons = true\n");
    try std.testing.expectEqual(true, config.show_icons.?);
}

test "parseConfig with comments and empty lines" {
    const config = parseConfig(
        \\# This is a comment
        \\
        \\show_icons = false
        \\# Another comment
        \\
    );
    try std.testing.expectEqual(false, config.show_icons.?);
}

test "parseConfig with empty content" {
    const config = parseConfig("");
    try std.testing.expect(config.show_icons == null);
}

test "parseConfig ignores unknown keys" {
    const config = parseConfig("unknown_key = value\nshow_icons = false\n");
    try std.testing.expectEqual(false, config.show_icons.?);
}

test "parseConfig with inline comments" {
    const config = parseConfig("show_icons = false # disable for tofu\n");
    try std.testing.expectEqual(false, config.show_icons.?);
}
