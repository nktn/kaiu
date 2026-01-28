---
name: tui-double-click-detection
description: Reliable double-click detection in TUI applications using monotonic time
---

# TUI Double-Click Detection with Monotonic Time

**Extracted:** 2026-01-28
**Context:** kaiu Phase 3.5 - US2 (Double-click to expand/preview)

## Problem

Detecting double-clicks in a TUI application requires:
1. Tracking time between clicks reliably (not affected by system time changes)
2. Distinguishing between clicks on the same vs. different entries
3. Handling scroll events that change which entry is at a given screen row

## Solution

Use `std.time.Instant` (monotonic time) with entry-based tracking:

```zig
pub const App = struct {
    // Double-click detection state
    last_click_time: ?std.time.Instant, // Monotonic timestamp
    last_click_entry: ?usize,           // Visible index (scroll-adjusted)

    const double_click_threshold_ns: u64 = 400_000_000; // 400ms
};

fn handleLeftClick(self: *Self, screen_row: u16) void {
    const target_visible = self.scroll_offset + screen_row;

    // Check if this is a double-click
    const is_double_click = blk: {
        const last_time = self.last_click_time orelse break :blk false;
        const last_entry = self.last_click_entry orelse break :blk false;

        const now = std.time.Instant.now() catch break :blk false;
        const elapsed = now.since(last_time);

        // Same entry AND within threshold
        break :blk (last_entry == target_visible and
                    elapsed < double_click_threshold_ns);
    };

    if (is_double_click) {
        // Execute double-click action
        self.handleDoubleClick();
        // Reset tracking to prevent triple-click as second double-click
        self.last_click_time = null;
        self.last_click_entry = null;
    } else {
        // Single click - update tracking
        const now = std.time.Instant.now() catch return;
        self.last_click_time = now;
        self.last_click_entry = target_visible;

        // Execute single-click action
        self.moveCursor(target_visible);
    }
}
```

## Key Decisions

### Why `std.time.Instant`?

**Monotonic time** is essential for intervals:
- `std.time.timestamp()` returns wall clock time (can jump backward/forward)
- `std.time.Instant` is guaranteed monotonic (always increases)
- System time changes (NTP sync, DST) don't affect measurement

### Why track entry index instead of screen row?

After scrolling, the same screen row may display a different entry:
- Screen row 5 before scroll → Entry A
- User scrolls down
- Screen row 5 after scroll → Entry B
- Click on row 5 should NOT be a double-click

Tracking `scroll_offset + screen_row` (visible index) ensures we detect clicks on the **same entry**.

### Why reset tracking after double-click?

Prevents this sequence from being two double-clicks:
```
Click 1 (entry A, t=0)
Click 2 (entry A, t=300ms) → Double-click detected
Click 3 (entry A, t=600ms) → Should be single click, not another double-click
```

## Threshold Selection

Common double-click thresholds:
- **300ms**: Fast (requires precision)
- **400ms**: Standard (most desktop environments)
- **500ms**: Generous (easier for users)

kaiu uses **400ms** to match desktop conventions.

## When to Use

This pattern applies to any TUI application that needs double-click detection:
- File managers (expand directories)
- Text editors (select words)
- Data browsers (drill down into items)

## Alternatives Considered

1. **Wall clock time** (`std.time.milliTimestamp()`):
   - Simpler API
   - **Rejected**: Not monotonic, can break on system time changes

2. **Screen row tracking**:
   - Simpler state (no need to calculate visible index)
   - **Rejected**: Breaks after scrolling

3. **Triple-click as second double-click**:
   - Allows rapid repeated actions
   - **Rejected**: Confusing UX, non-standard behavior

## Testing

Key test cases:
```zig
test "double-click detection: same entry within threshold" {
    // Click entry 0 at t=0
    // Click entry 0 at t=300ms
    // → Should detect double-click
}

test "double-click detection: different entries" {
    // Click entry 0 at t=0
    // Click entry 1 at t=300ms
    // → Should be two single clicks
}

test "double-click detection: same entry after threshold" {
    // Click entry 0 at t=0
    // Click entry 0 at t=500ms (> 400ms threshold)
    // → Should be two single clicks
}

test "double-click detection: reset after double-click" {
    // Click entry 0 at t=0
    // Click entry 0 at t=300ms → Double-click
    // Click entry 0 at t=600ms → Single click (not double-click)
}
```

## References

- kaiu: `src/app.zig` - `handleLeftClick()`, `handleDoubleClick()`
- Zig std: `std.time.Instant` documentation
- Desktop environments: GNOME (400ms), Windows (default 500ms), macOS (click speed preference)
