//! File system watching module.
//!
//! Provides file system monitoring for auto-refresh functionality.
//! Uses modification time polling for cross-platform compatibility.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// File system watch event types.
pub const WatchEvent = enum {
    created,
    deleted,
    modified,
    renamed,
};

/// Polling-based watcher implementation.
/// Checks directory modification time to detect changes.
pub const Watcher = struct {
    allocator: Allocator,
    path: []const u8,
    enabled: bool,
    last_mtime: i128,
    poll_interval_ms: u64,
    last_poll_time: i64,

    const DEFAULT_POLL_INTERVAL_MS: u64 = 500; // Check every 500ms

    /// Initialize watcher for the given directory path (T051).
    pub fn init(allocator: Allocator, path: []const u8) !*Watcher {
        const self = try allocator.create(Watcher);
        errdefer allocator.destroy(self);

        // Get initial modification time
        const initial_mtime = getDirectoryMtime(path) catch 0;

        self.* = .{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .enabled = true, // Enabled by default, user can toggle with 'W'
            .last_mtime = initial_mtime,
            .poll_interval_ms = DEFAULT_POLL_INTERVAL_MS,
            .last_poll_time = 0,
        };

        return self;
    }

    /// Cleanup watcher resources (T052).
    pub fn deinit(self: *Watcher) void {
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// Non-blocking poll for file system events (T053).
    /// Returns true if there were events that require a tree refresh.
    pub fn poll(self: *Watcher) bool {
        if (!self.enabled) return false;

        // Throttle polling to avoid excessive filesystem access
        const now = std.time.milliTimestamp();
        if (now - self.last_poll_time < @as(i64, @intCast(self.poll_interval_ms))) {
            return false;
        }
        self.last_poll_time = now;

        // Check if directory modification time has changed
        const current_mtime = getDirectoryMtime(self.path) catch return false;

        if (current_mtime != self.last_mtime) {
            self.last_mtime = current_mtime;
            return true;
        }

        return false;
    }

    /// Enable or disable the watcher.
    pub fn setEnabled(self: *Watcher, enabled: bool) void {
        self.enabled = enabled;
        if (enabled) {
            // Reset mtime when enabling to avoid false positive on first poll
            self.last_mtime = getDirectoryMtime(self.path) catch 0;
            self.last_poll_time = 0;
        }
    }

    /// Check if watcher is enabled.
    pub fn isEnabled(self: *const Watcher) bool {
        return self.enabled;
    }

    /// Update the watched path (e.g., when tree root changes).
    pub fn updatePath(self: *Watcher, new_path: []const u8) !void {
        self.allocator.free(self.path);
        self.path = try self.allocator.dupe(u8, new_path);
        self.last_mtime = getDirectoryMtime(new_path) catch 0;
    }
};

/// Get the modification time of a directory.
/// Returns the mtime in nanoseconds since epoch.
fn getDirectoryMtime(path: []const u8) !i128 {
    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();

    const stat = try dir.stat();
    return stat.mtime;
}

/// Debounce helper for file system events.
pub const Debouncer = struct {
    last_event_time: i64,
    pending: bool,
    debounce_ms: u32,

    pub fn init(debounce_ms: u32) Debouncer {
        return .{
            .last_event_time = 0,
            .pending = false,
            .debounce_ms = debounce_ms,
        };
    }

    /// Record an event. Returns true if should trigger refresh now.
    pub fn recordEvent(self: *Debouncer) bool {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_event_time;

        if (elapsed >= self.debounce_ms) {
            // Enough time has passed, trigger immediately
            self.last_event_time = now;
            self.pending = false;
            return true;
        } else {
            // Within debounce window, mark as pending
            self.pending = true;
            return false;
        }
    }

    /// Check if a pending event should now trigger.
    pub fn checkPending(self: *Debouncer) bool {
        if (!self.pending) return false;

        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_event_time;

        if (elapsed >= self.debounce_ms) {
            self.last_event_time = now;
            self.pending = false;
            return true;
        }

        return false;
    }

    /// Reset debouncer state.
    pub fn reset(self: *Debouncer) void {
        self.last_event_time = 0;
        self.pending = false;
    }
};

test "Debouncer init" {
    const debouncer = Debouncer.init(300);
    try std.testing.expectEqual(@as(u32, 300), debouncer.debounce_ms);
    try std.testing.expect(!debouncer.pending);
}

test "Watcher init and deinit" {
    const allocator = std.testing.allocator;

    // Use temp directory for test
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const watcher = try Watcher.init(allocator, path);
    defer watcher.deinit();

    try std.testing.expect(watcher.enabled);
    try std.testing.expectEqualStrings(path, watcher.path);
}

test "Watcher enable/disable" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const watcher = try Watcher.init(allocator, path);
    defer watcher.deinit();

    try std.testing.expect(watcher.isEnabled());

    watcher.setEnabled(false);
    try std.testing.expect(!watcher.isEnabled());

    watcher.setEnabled(true);
    try std.testing.expect(watcher.isEnabled());
}
