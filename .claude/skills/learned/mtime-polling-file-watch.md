---
name: mtime-polling-file-watch
description: Cross-platform file system watching via mtime polling
---

# Mtime Polling File Watch Pattern

**Extracted:** 2026-01-26
**Context:** Detecting external file system changes for auto-refresh in TUI apps

## Problem

TUI file explorers need to detect when the file system changes externally (e.g., files added/deleted/modified by other programs). Platform-specific APIs exist:
- Linux: inotify
- macOS: FSEvents, kqueue
- Windows: ReadDirectoryChangesW

But they have drawbacks:
- Complex setup and event handling
- Platform-specific code paths
- May miss events (buffer overflow)
- Require event loop integration

## Solution: Mtime Polling

Poll directory modification time (mtime) at regular intervals.

### Implementation

```zig
pub const Watcher = struct {
    allocator: Allocator,
    path: []const u8,
    enabled: bool,
    last_mtime: i128,
    poll_interval_ms: u64,
    last_poll_time: i64,

    const DEFAULT_POLL_INTERVAL_MS: u64 = 500; // Check every 500ms

    pub fn init(allocator: Allocator, path: []const u8) !*Watcher {
        const initial_mtime = try getDirectoryMtime(path);

        const self = try allocator.create(Watcher);
        self.* = .{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .enabled = true,
            .last_mtime = initial_mtime,
            .poll_interval_ms = DEFAULT_POLL_INTERVAL_MS,
            .last_poll_time = 0,
        };

        return self;
    }

    pub fn poll(self: *Watcher) bool {
        if (!self.enabled) return false;

        // Throttle polling
        const now = std.time.milliTimestamp();
        if (now - self.last_poll_time < @as(i64, @intCast(self.poll_interval_ms))) {
            return false;
        }
        self.last_poll_time = now;

        // Check mtime
        const current_mtime = getDirectoryMtime(self.path) catch return false;

        if (current_mtime != self.last_mtime) {
            self.last_mtime = current_mtime;
            return true; // Tree refresh needed
        }

        return false;
    }
};

fn getDirectoryMtime(path: []const u8) !i128 {
    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();

    const stat = try dir.stat();
    return stat.mtime;
}
```

### Integration with Event Loop

```zig
// In main event loop
pub fn run(self: *App) !void {
    while (!self.should_quit) {
        // Handle user input
        while (self.loop.tryEvent()) |event| {
            try self.handleEvent(event);
        }

        // Poll watcher (non-blocking)
        if (self.watcher) |watcher| {
            if (watcher.poll()) {
                // External change detected - reload tree
                try self.reloadTree();
            }
        }

        // Render
        try self.render();

        // Wait for next event (with timeout for periodic polling)
        const timeout_ns = 100 * std.time.ns_per_ms; // 100ms
        _ = self.vx.nextEvent() catch |err| switch (err) {
            error.WouldBlock => {}, // Timeout - continue polling
            else => return err,
        };
    }
}
```

## When to Use

**Use mtime polling when:**
- Need cross-platform file watching
- Occasional changes expected (not high-frequency)
- Simplicity is preferred over low latency
- 500ms-1s delay is acceptable

**Do NOT use when:**
- Need instant detection (<100ms)
- Watching many directories simultaneously (inotify scales better)
- High-frequency changes (log files, build outputs)
- Need to detect which specific files changed (mtime only tells if directory changed)

## Optimizations

### Debouncing

Multiple changes in quick succession should trigger only one refresh:

```zig
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

    pub fn recordEvent(self: *Debouncer) bool {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_event_time;

        if (elapsed >= self.debounce_ms) {
            self.last_event_time = now;
            self.pending = false;
            return true; // Trigger refresh now
        } else {
            self.pending = true;
            return false; // Wait for debounce window
        }
    }

    pub fn checkPending(self: *Debouncer) bool {
        if (!self.pending) return false;

        const now = std.time.milliTimestamp();
        if (now - self.last_event_time >= self.debounce_ms) {
            self.pending = false;
            return true; // Trigger deferred refresh
        }
        return false;
    }
};
```

Usage:
```zig
var debouncer = Debouncer.init(300); // 300ms debounce

if (watcher.poll()) {
    if (debouncer.recordEvent()) {
        try self.reloadTree();
    }
}

// In event loop
if (debouncer.checkPending()) {
    try self.reloadTree();
}
```

### Recursive Watching

To watch subdirectories, maintain a map of paths to mtimes:

```zig
pub const RecursiveWatcher = struct {
    allocator: Allocator,
    mtimes: std.StringHashMap(i128),

    pub fn poll(self: *RecursiveWatcher, root: []const u8) !bool {
        var changed = false;
        var walker = try std.fs.walkPath(self.allocator, root);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .directory) continue;

            const current_mtime = try getDirectoryMtime(entry.path);
            const result = try self.mtimes.getOrPut(entry.path);

            if (!result.found_existing or result.value_ptr.* != current_mtime) {
                result.value_ptr.* = current_mtime;
                changed = true;
            }
        }

        return changed;
    }
};
```

**Note:** Recursive watching is expensive - prefer single directory polling.

## Limitations

### Mtime Granularity
- Some filesystems have 1-second mtime granularity (FAT32)
- Rapid changes within 1 second may be missed
- Solution: Use hash of directory listing for precise detection

### False Positives
- Mtime changes on metadata updates (permissions, ownership)
- Not all mtime changes are file additions/deletions
- Solution: Accept occasional unnecessary refreshes

### Network Filesystems
- NFS/SMB may cache mtime values
- Delays of several seconds possible
- Solution: Increase poll interval (1-2 seconds)

## Alternative Approaches

### Platform-Specific APIs

```zig
// Linux: inotify
const fd = try std.os.inotify_init1(std.os.linux.IN.NONBLOCK);
defer std.os.close(fd);

const wd = try std.os.inotify_add_watch(fd, path,
    std.os.linux.IN.CREATE | std.os.linux.IN.DELETE | std.os.linux.IN.MODIFY);

// macOS: FSEvents (requires C API)
// Windows: ReadDirectoryChangesW (requires Windows API)
```

**Trade-off:** Platform-specific code vs. simplicity and portability.

### File Listing Hash

```zig
fn getDirectoryHash(path: []const u8) !u64 {
    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();

    var hasher = std.hash.Wyhash.init(0);
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        hasher.update(entry.name);
    }

    return hasher.final();
}
```

**Trade-off:** More accurate detection, but higher CPU cost.

## References

- [Zig std.fs.File.stat()](https://ziglang.org/documentation/master/std/#std.fs.File.stat)
- [Linux inotify](https://man7.org/linux/man-pages/man7/inotify.7.html)
- [macOS FSEvents](https://developer.apple.com/documentation/coreservices/file_system_events)

## Related Patterns

- Debouncing pattern (documented above)
- Event loop integration (TUI-specific)
- Tree reload strategies (not yet documented)
