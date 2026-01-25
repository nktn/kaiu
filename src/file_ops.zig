const std = @import("std");

/// File operations module - extracted from app.zig
/// Provides pure file system operations without App dependencies

pub const ClipboardOperation = enum {
    none,
    copy,
    cut,
};

// ===== Helper Functions =====

/// Validate filename - reject path separators and parent directory references
/// to prevent path traversal attacks
pub fn isValidFilename(name: []const u8) bool {
    if (name.len == 0) return false;

    // Reject path separators
    if (std.mem.indexOf(u8, name, "/") != null) return false;
    if (std.mem.indexOf(u8, name, "\\") != null) return false;

    // Reject parent directory reference
    if (std.mem.eql(u8, name, "..")) return false;
    if (std.mem.eql(u8, name, ".")) return false;

    return true;
}

/// Base64 encode for OSC 52 clipboard
pub fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
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

/// Copy a file or directory (standalone function)
pub fn copyPath(src: []const u8, dest: []const u8) !void {
    const stat = try std.fs.cwd().statFile(src);
    if (stat.kind == .directory) {
        // Copy directory recursively
        try copyDirRecursive(src, dest);
    } else {
        // Copy file
        try std.fs.cwd().copyFile(src, std.fs.cwd(), dest, .{});
    }
}

/// Delete a file or directory recursively with symlink safety
pub fn deletePathRecursive(path: []const u8) !void {
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

/// Copy a directory recursively with symlink safety
/// Copies directory recursively, preserving symlinks as symlinks (not following them)
/// Returns error if any file copy fails (to prevent data loss on cut operations)
pub fn copyDirRecursive(src_path: []const u8, dest_path: []const u8) !void {
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check if source is a symlink - if so, copy the symlink itself
    if (std.fs.cwd().readLink(src_path, &link_buf)) |link_target| {
        // Copy symlink: create a new symlink at dest_path pointing to the same target
        std.posix.symlink(link_target, dest_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
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

    // Iterate and copy - propagate errors to prevent partial copy + delete
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        fba.reset();
        const src_child = try std.fs.path.join(allocator, &.{ src_path, entry.name });
        const dest_child = try std.fs.path.join(allocator, &.{ dest_path, entry.name });

        // Check for symlink - copy as symlink, not following it
        if (std.fs.cwd().readLink(src_child, &link_buf)) |link_target| {
            std.posix.symlink(link_target, dest_child) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
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

/// Format path for display, replacing home directory with ~
/// Caller must free the returned string.
pub fn formatDisplayPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
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
pub fn isBinaryContent(content: []const u8) bool {
    // Check first 8KB for null bytes
    const check_len = @min(content.len, 8192);
    for (content[0..check_len]) |byte| {
        if (byte == 0) return true;
    }
    return false;
}

// ===== Tests =====

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
    var read_buf: [64]u8 = undefined;
    const len = try read_file.readAll(&read_buf);
    try std.testing.expectEqualStrings(test_content, read_buf[0..len]);
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

    // Verify nested structure
    var dest_sub = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_sub.close();
    var nested_dir = try dest_sub.openDir("sub", .{});
    defer nested_dir.close();
    _ = try nested_dir.statFile("nested.txt");
}

test "copyDirRecursive copies symlinks" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create source directory with a file and a symlink
    try tmp_dir.dir.makeDir("src_symlink");
    var src_dir = try tmp_dir.dir.openDir("src_symlink", .{});

    // Create a target file
    var target_file = try src_dir.createFile("target.txt", .{});
    try target_file.writeAll("target content");
    target_file.close();

    // Create a symlink to the target file
    try std.posix.symlinkat("target.txt", src_dir.fd, "link.txt");
    src_dir.close();

    const src_path = try tmp_dir.dir.realpathAlloc(allocator, "src_symlink");
    defer allocator.free(src_path);
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    const dest_path = try std.fs.path.join(allocator, &.{ base_path, "dest_symlink" });
    defer allocator.free(dest_path);

    try copyDirRecursive(src_path, dest_path);

    // Verify symlink was copied (not the target file)
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    // Check that link.txt exists and is a symlink
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    const link_target = try dest_dir.readLink("link.txt", &link_buf);
    try std.testing.expectEqualStrings("target.txt", link_target);

    // Verify target file was also copied
    _ = try dest_dir.statFile("target.txt");
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
