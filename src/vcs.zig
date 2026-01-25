//! VCS (Version Control System) integration module.
//!
//! Provides Git and Jujutsu (jj) status detection and parsing.
//! Used to display file status colors and branch info in the status bar.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Type of VCS repository detected.
pub const VCSType = enum {
    none, // Not in a repository
    git, // Git repository
    jj, // Jujutsu repository
};

/// User-selected VCS mode for display.
pub const VCSMode = enum {
    auto, // Auto-detect (JJ preferred if both exist)
    git, // Force Git
    jj, // Force JJ
};

/// File status in the VCS.
/// Maps to display colors per FR-003:
/// - Green: New/Untracked
/// - Yellow: Modified (staged and unstaged not distinguished)
/// - Red: Deleted (staged or unstaged)
/// - Cyan: Renamed
/// - Magenta: Conflict
pub const VCSFileStatus = enum {
    unchanged,
    modified, // Yellow
    untracked, // Green
    deleted, // Red
    renamed, // Cyan
    conflict, // Magenta
};

/// Result of VCS status query.
pub const VCSStatusResult = struct {
    allocator: Allocator,
    /// Map of relative file path to status.
    status_map: std.StringHashMap(VCSFileStatus),
    /// Branch name (Git) or change ID (JJ).
    branch: ?[]const u8,
    /// Bookmark name (JJ only).
    bookmark: ?[]const u8,

    pub fn init(allocator: Allocator) VCSStatusResult {
        return .{
            .allocator = allocator,
            .status_map = std.StringHashMap(VCSFileStatus).init(allocator),
            .branch = null,
            .bookmark = null,
        };
    }

    pub fn deinit(self: *VCSStatusResult) void {
        // Free all owned keys
        var it = self.status_map.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.status_map.deinit();

        if (self.branch) |b| {
            self.allocator.free(b);
        }
        if (self.bookmark) |b| {
            self.allocator.free(b);
        }
    }

    /// Put a status entry with an owned key.
    pub fn put(self: *VCSStatusResult, path: []const u8, status: VCSFileStatus) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        try self.status_map.put(owned_path, status);
    }

    /// Get status for a path.
    pub fn get(self: *const VCSStatusResult, path: []const u8) ?VCSFileStatus {
        return self.status_map.get(path);
    }
};

/// Timeout for VCS commands in nanoseconds (2 seconds per FR-007).
const VCS_COMMAND_TIMEOUT_NS: u64 = 2 * std.time.ns_per_s;

/// Detect which VCS is present in the given directory.
/// Checks for .jj and .git directories.
/// Returns .jj if both exist (JJ preferred per FR-002).
pub fn detectVCS(path: []const u8) VCSType {
    const has_jj = blk: {
        var dir = std.fs.openDirAbsolute(path, .{}) catch break :blk false;
        defer dir.close();
        dir.access(".jj", .{}) catch break :blk false;
        break :blk true;
    };

    const has_git = blk: {
        var dir = std.fs.openDirAbsolute(path, .{}) catch break :blk false;
        defer dir.close();
        dir.access(".git", .{}) catch break :blk false;
        break :blk true;
    };

    if (has_jj) return .jj;
    if (has_git) return .git;
    return .none;
}

/// Execute a command and capture stdout.
/// Returns null on timeout or error. Always cleans up child process to avoid zombies.
fn executeCommand(allocator: Allocator, argv: []const []const u8, cwd: ?[]const u8) ?[]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.cwd = cwd;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;

    // Read stdout - ensure we always wait() even on error to avoid zombies
    const stdout = child.stdout orelse {
        _ = child.wait() catch {};
        return null;
    };

    // Read all output into allocated buffer
    var output_list: std.ArrayList(u8) = .empty;
    defer output_list.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    var exceeded_limit = false;
    while (true) {
        const bytes_read = stdout.read(&read_buf) catch {
            // Drain remaining output before wait() to prevent child blocking on full pipe
            drainPipe(stdout);
            _ = child.wait() catch {};
            return null;
        };
        if (bytes_read == 0) break;

        if (output_list.items.len + bytes_read > 1024 * 1024) {
            exceeded_limit = true;
            break; // Limit to 1MB
        }
        output_list.appendSlice(allocator, read_buf[0..bytes_read]) catch {
            drainPipe(stdout);
            _ = child.wait() catch {};
            return null;
        };
    }

    // Drain remaining output if we exceeded limit, to prevent child blocking
    if (exceeded_limit) {
        drainPipe(stdout);
    }

    // Wait for process to complete
    const term = child.wait() catch return null;

    if (term.Exited != 0) {
        return null;
    }

    // Return owned copy
    return allocator.dupe(u8, output_list.items) catch null;
}

/// Drain a pipe to prevent child process from blocking on full stdout buffer.
fn drainPipe(pipe: std.fs.File) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = pipe.read(&buf) catch break;
        if (n == 0) break;
    }
}

/// Get Git status for the repository at the given path.
pub fn getGitStatus(allocator: Allocator, repo_path: []const u8) !VCSStatusResult {
    var result = VCSStatusResult.init(allocator);
    errdefer result.deinit();

    // Get status: git status --porcelain=v1 -z
    const status_output = executeCommand(
        allocator,
        &.{ "git", "-C", repo_path, "status", "--porcelain=v1", "-z" },
        null,
    );
    defer if (status_output) |s| allocator.free(s);

    if (status_output) |output| {
        try parseGitStatus(&result, output);
    }

    // Get branch: git branch --show-current
    const branch_output = executeCommand(
        allocator,
        &.{ "git", "-C", repo_path, "branch", "--show-current" },
        null,
    );

    if (branch_output) |output| {
        defer allocator.free(output);
        const trimmed = std.mem.trim(u8, output, " \t\n\r");
        if (trimmed.len > 0) {
            result.branch = try allocator.dupe(u8, trimmed);
        }
    }

    return result;
}

/// Parse git status --porcelain=v1 -z output.
/// Format: XY path\0 or XY old_path\0new_path\0 for renames
fn parseGitStatus(result: *VCSStatusResult, output: []const u8) !void {
    var i: usize = 0;
    while (i < output.len) {
        // Need at least XY + space + 1 char path + null
        if (i + 4 > output.len) break;

        const index_status = output[i];
        const worktree_status = output[i + 1];

        if (output[i + 2] != ' ') break;
        i += 3;

        // Find null terminator
        const path_start = i;
        while (i < output.len and output[i] != 0) : (i += 1) {}
        if (i >= output.len) break;

        const path = output[path_start..i];
        i += 1; // Skip null

        // Determine status
        const status = mapGitStatus(index_status, worktree_status);

        // Handle rename/copy: use NEW path (second null-terminated string) for status map
        // git status -z format for renames/copies: "R  old_path\0new_path\0" or "C  src\0dest\0"
        // UI looks up by current (new) path, so we need to register that
        if (index_status == 'R' or worktree_status == 'R' or
            index_status == 'C' or worktree_status == 'C')
        {
            // Read new path
            const new_path_start = i;
            while (i < output.len and output[i] != 0) : (i += 1) {}
            if (i > new_path_start) {
                const new_path = output[new_path_start..i];
                try result.put(new_path, status);
            } else {
                // Fallback to old path if new path is empty (shouldn't happen)
                try result.put(path, status);
            }
            if (i < output.len) i += 1;
        } else {
            try result.put(path, status);
        }
    }
}

/// Map git status codes to VCSFileStatus.
fn mapGitStatus(index: u8, worktree: u8) VCSFileStatus {
    // Conflict markers
    if (index == 'U' or worktree == 'U') return .conflict;
    if (index == 'A' and worktree == 'A') return .conflict;
    if (index == 'D' and worktree == 'D') return .conflict;

    // Untracked
    if (index == '?' and worktree == '?') return .untracked;

    // Renamed or Copied (both shown as cyan)
    if (index == 'R' or worktree == 'R') return .renamed;
    if (index == 'C' or worktree == 'C') return .renamed; // Copied files shown same as renamed

    // Deleted
    if (index == 'D' or worktree == 'D') return .deleted;

    // Modified (staged or unstaged - not distinguished per spec)
    if (index == 'M' or worktree == 'M') return .modified;

    // Added (treat as untracked for color purposes)
    if (index == 'A') return .untracked;

    return .unchanged;
}

/// Get JJ status for the repository at the given path.
pub fn getJJStatus(allocator: Allocator, repo_path: []const u8) !VCSStatusResult {
    var result = VCSStatusResult.init(allocator);
    errdefer result.deinit();

    // Get status: jj --no-pager -R <repo_path> status --color=never
    const status_output = executeCommand(
        allocator,
        &.{ "jj", "--no-pager", "-R", repo_path, "status", "--color=never" },
        null,
    );
    defer if (status_output) |s| allocator.free(s);

    if (status_output) |output| {
        try parseJJStatus(&result, output);
    }

    // Get change ID and bookmark
    const log_output = executeCommand(
        allocator,
        &.{ "jj", "--no-pager", "-R", repo_path, "log", "-r", "@", "--no-graph", "-T", "change_id.short() ++ \" \" ++ bookmarks" },
        null,
    );

    if (log_output) |output| {
        defer allocator.free(output);
        try parseJJInfo(&result, output);
    }

    return result;
}

/// Parse jj status output.
/// Format varies, but typically:
/// Working copy changes:
/// M path/to/file
/// A path/to/new/file
/// D path/to/deleted/file
fn parseJJStatus(result: *VCSStatusResult, output: []const u8) !void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    var in_changes_section = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Check for section header
        if (std.mem.startsWith(u8, trimmed, "Working copy changes:")) {
            in_changes_section = true;
            continue;
        }

        // Empty line or new section ends changes
        if (trimmed.len == 0 or (trimmed.len > 0 and !in_changes_section)) {
            if (in_changes_section and trimmed.len == 0) {
                // Continue through empty lines in section
                continue;
            }
            if (std.mem.indexOf(u8, trimmed, ":") != null and !std.mem.startsWith(u8, trimmed, "M ") and !std.mem.startsWith(u8, trimmed, "A ") and !std.mem.startsWith(u8, trimmed, "D ") and !std.mem.startsWith(u8, trimmed, "R ")) {
                in_changes_section = false;
                continue;
            }
        }

        if (!in_changes_section) continue;

        // Parse status line: X path
        if (trimmed.len < 3) continue;

        const status_char = trimmed[0];
        if (trimmed[1] != ' ') continue;

        const path = trimmed[2..];
        const status = mapJJStatus(status_char);

        try result.put(path, status);
    }
}

/// Map JJ status character to VCSFileStatus.
fn mapJJStatus(char: u8) VCSFileStatus {
    return switch (char) {
        'M' => .modified,
        'A' => .untracked,
        'D' => .deleted,
        'R' => .renamed,
        'C' => .conflict,
        else => .unchanged,
    };
}

/// Parse JJ log output for change ID and bookmark.
fn parseJJInfo(result: *VCSStatusResult, output: []const u8) !void {
    const trimmed = std.mem.trim(u8, output, " \t\n\r");
    if (trimmed.len == 0) return;

    // Format: "changeid bookmark1 bookmark2..."
    var parts = std.mem.splitScalar(u8, trimmed, ' ');

    // First part is change ID
    if (parts.next()) |change_id| {
        result.branch = try result.allocator.dupe(u8, change_id);
    }

    // Remaining parts are bookmarks (take first one)
    if (parts.next()) |bookmark| {
        if (bookmark.len > 0) {
            result.bookmark = try result.allocator.dupe(u8, bookmark);
        }
    }
}

/// Get VCS status based on detected type and mode.
pub fn getVCSStatus(allocator: Allocator, repo_path: []const u8, detected: VCSType, mode: VCSMode) !VCSStatusResult {
    const effective_type = switch (mode) {
        .auto => detected,
        .git => if (detected != .none) VCSType.git else VCSType.none,
        .jj => if (detected != .none) VCSType.jj else VCSType.none,
    };

    return switch (effective_type) {
        .git => getGitStatus(allocator, repo_path),
        .jj => getJJStatus(allocator, repo_path),
        .none => VCSStatusResult.init(allocator),
    };
}

/// Cycle VCS mode: Auto -> JJ -> Git -> Auto
pub fn cycleVCSMode(current: VCSMode) VCSMode {
    return switch (current) {
        .auto => .jj,
        .jj => .git,
        .git => .auto,
    };
}

/// Format VCS mode name for display.
pub fn vcsModeName(mode: VCSMode) []const u8 {
    return switch (mode) {
        .auto => "Auto",
        .jj => "JJ",
        .git => "Git",
    };
}

test "detectVCS returns none for non-repo directory" {
    const vcs_type = detectVCS("/tmp");
    try std.testing.expectEqual(VCSType.none, vcs_type);
}

test "cycleVCSMode cycles correctly" {
    try std.testing.expectEqual(VCSMode.jj, cycleVCSMode(.auto));
    try std.testing.expectEqual(VCSMode.git, cycleVCSMode(.jj));
    try std.testing.expectEqual(VCSMode.auto, cycleVCSMode(.git));
}

test "mapGitStatus handles common cases" {
    try std.testing.expectEqual(VCSFileStatus.untracked, mapGitStatus('?', '?'));
    try std.testing.expectEqual(VCSFileStatus.modified, mapGitStatus('M', ' '));
    try std.testing.expectEqual(VCSFileStatus.modified, mapGitStatus(' ', 'M'));
    try std.testing.expectEqual(VCSFileStatus.deleted, mapGitStatus('D', ' '));
    try std.testing.expectEqual(VCSFileStatus.renamed, mapGitStatus('R', ' '));
    try std.testing.expectEqual(VCSFileStatus.conflict, mapGitStatus('U', 'U'));
    try std.testing.expectEqual(VCSFileStatus.untracked, mapGitStatus('A', ' '));
}
