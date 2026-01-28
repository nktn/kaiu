---
name: tui-status-bar-caching
description: Optimize expensive stat() calls with cursor-based caching in TUI applications
---

# TUI Status Bar Caching Pattern

**Extracted:** 2026-01-28
**Context:** kaiu Phase 3.5 - US3 (File info in status bar)

## Problem

Displaying file information (size, modification time) in a status bar requires `stat()` system calls:
- Expensive operation (I/O)
- Called on every render (60+ FPS)
- Degrades performance with many cursor movements

Example naive implementation:
```zig
fn renderStatusBar(self: *Self) !void {
    const entry = self.getCurrentEntry();
    const stat = try std.fs.cwd().statFile(entry.path); // EXPENSIVE!
    // Display stat.size, stat.mtime...
}
```

**Performance impact**: 60 FPS × stat() per frame = 60+ syscalls/second (unnecessary)

## Solution

Cache file info and invalidate only when cursor moves:

```zig
pub const App = struct {
    // Status bar cache
    cached_file_info: ?CachedFileInfo,
    cached_file_info_cursor: ?usize, // Cursor position when cached

    pub const CachedFileInfo = struct {
        name: []const u8,    // Borrowed from FileEntry (not owned)
        size: ?u64,          // null if stat failed
        mtime_sec: ?i128,    // null if stat failed
        is_dir: bool,
        item_count: ?usize,  // For directories
    };
};

fn updateCachedFileInfo(self: *Self) void {
    // Check if cursor moved
    if (self.cached_file_info_cursor) |cached_cursor| {
        if (cached_cursor == self.cursor) {
            return; // Cache still valid
        }
    }

    // Cursor moved - invalidate cache
    self.cached_file_info = null;
    self.cached_file_info_cursor = null;

    // Get current entry
    const entry = self.getCurrentEntry() orelse {
        return; // No entry at cursor
    };

    // Attempt stat (may fail)
    const stat_result = std.fs.cwd().statFile(entry.path) catch {
        // stat failed - cache with nulls
        self.cached_file_info = .{
            .name = entry.name,
            .size = null,
            .mtime_sec = null,
            .is_dir = entry.kind == .directory,
            .item_count = null,
        };
        self.cached_file_info_cursor = self.cursor;
        return;
    };

    // Cache successful stat result
    self.cached_file_info = .{
        .name = entry.name,
        .size = stat_result.size,
        .mtime_sec = stat_result.mtime,
        .is_dir = entry.kind == .directory,
        .item_count = if (entry.kind == .directory)
            countDirectoryItems(entry)
        else
            null,
    };
    self.cached_file_info_cursor = self.cursor;
}

fn renderStatusBar(self: *Self) !void {
    // Use cached info (already computed)
    if (self.cached_file_info) |info| {
        const size_str = if (info.size) |s|
            try formatSize(arena, s)
        else
            "-"; // stat failed

        const time_str = if (info.mtime_sec) |mtime|
            try formatRelativeTime(arena, mtime, now)
        else
            "-"; // stat failed

        // Render...
    }
}
```

## When to Update Cache

Call `updateCachedFileInfo()` after any operation that may change the cursor:

```zig
fn moveCursor(self: *Self, new_pos: usize) void {
    self.cursor = new_pos;
    self.updateScrollOffset();
    self.updateCachedFileInfo(); // Invalidate and refresh
}

fn expandOrEnter(self: *Self) !void {
    // ... expand/enter logic ...
    self.updateCachedFileInfo(); // Cursor may have moved
}

fn handleLeftClick(self: *Self, screen_row: u16) void {
    self.moveCursor(target_visible);
    self.updateCachedFileInfo(); // Explicit call (moveCursor already does it)
}
```

## Performance Impact

**Before caching:**
- 60 FPS × `stat()` = 60+ syscalls/second
- Noticeable lag on cursor movement

**After caching:**
- 1 `stat()` per cursor move
- Instant rendering from cache
- ~60x reduction in syscalls

## Key Design Decisions

### Why cache cursor position instead of entry path?

**Cursor-based invalidation** is simpler and more reliable:
- No need to compare paths (string equality check)
- Works even if entry path changes (rare but possible)
- Matches user mental model ("cache is for current position")

### Why allow null values in cache?

**Graceful degradation** when `stat()` fails:
- Broken symlinks
- Permission denied
- File deleted between tree read and stat

Display "-" instead of crashing or omitting the status bar.

### Why borrow name instead of copying?

**Zero-allocation principle**:
- `FileEntry.name` already exists in memory
- Cache only needs to point to it (not own it)
- Reduces allocator pressure

**Safety**: Cache is invalidated before tree modifications, so borrowed pointer never dangles.

## When to Use

This pattern applies when:
1. Status bar displays **computed** or **expensive** information
2. Information changes **only** when cursor moves
3. Cursor moves are **less frequent** than renders

## Alternatives Considered

1. **Path-based caching** (invalidate when path changes):
   - More complex string comparison
   - **Rejected**: Cursor-based is simpler and sufficient

2. **No caching** (compute every frame):
   - Simplest implementation
   - **Rejected**: Unacceptable performance degradation

3. **Pre-compute all entries** (cache entire tree):
   - No invalidation needed
   - **Rejected**: Memory overhead, stale data after external changes

## Testing

Key test cases:
```zig
test "cache invalidated on cursor move" {
    app.cursor = 0;
    app.updateCachedFileInfo();
    const cached_0 = app.cached_file_info;

    app.cursor = 1;
    app.updateCachedFileInfo();
    const cached_1 = app.cached_file_info;

    // Should be different entries
    try testing.expect(!std.mem.eql(u8, cached_0.name, cached_1.name));
}

test "cache reused when cursor unchanged" {
    app.cursor = 5;
    app.updateCachedFileInfo();
    const first_call_time = measureTime();

    app.updateCachedFileInfo(); // Second call
    const second_call_time = measureTime();

    // Second call should be instant (cache hit)
    try testing.expect(second_call_time < first_call_time / 10);
}

test "cache handles stat failure gracefully" {
    // Point cursor to inaccessible file
    app.cursor = index_of_broken_symlink;
    app.updateCachedFileInfo();

    // Should have cached with null values
    try testing.expectEqual(null, app.cached_file_info.?.size);
    try testing.expectEqual(null, app.cached_file_info.?.mtime_sec);
}
```

## References

- kaiu: `src/app.zig` - `updateCachedFileInfo()`, `renderStatusBar()`
- Related pattern: `.claude/skills/learned/tui-double-click-detection.md` (also uses cursor tracking)
