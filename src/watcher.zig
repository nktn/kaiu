//! File system watching module.
//!
//! Provides file system monitoring for auto-refresh functionality.
//! Uses FSEvents on macOS and inotify on Linux.

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

/// Platform-specific watcher implementation.
pub const Watcher = struct {
    allocator: Allocator,
    path: []const u8,
    enabled: bool,

    // Platform-specific state would go here
    // For now, this is a placeholder

    pub fn init(allocator: Allocator, path: []const u8) !*Watcher {
        const self = try allocator.create(Watcher);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .enabled = true,
        };

        return self;
    }

    pub fn deinit(self: *Watcher) void {
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// Non-blocking poll for file system events.
    /// Returns true if there were events that require a tree refresh.
    pub fn poll(self: *Watcher) bool {
        if (!self.enabled) return false;

        // Placeholder implementation
        // Real implementation would use:
        // - FSEvents on macOS
        // - inotify on Linux
        _ = self;
        return false;
    }

    /// Enable or disable the watcher.
    pub fn setEnabled(self: *Watcher, enabled: bool) void {
        self.enabled = enabled;
    }
};

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
