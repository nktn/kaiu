---
name: libvaxis-deferred-rendering-lifetime
description: Stack buffer lifetime issue with libvaxis printSegment
---

# libvaxis Deferred Rendering Lifetime

**Extracted:** 2026-01-29
**Context:** Using libvaxis for TUI rendering

## Problem

When passing stack-local buffers to `vaxis.Window.printSegment()`, the data may become invalid before actual rendering occurs because libvaxis uses deferred rendering.

```zig
// BAD: Stack buffer becomes invalid after function returns
fn renderIcon(win: vaxis.Window) void {
    var icon_buf: [4]u8 = undefined;
    const icon_len = std.unicode.utf8Encode(icon_codepoint, &icon_buf) catch return;

    // printSegment stores reference - but icon_buf is freed when function returns!
    _ = win.printSegment(.{ .text = icon_buf[0..icon_len] }, .{});
}
```

## Symptoms

- Icons/text appear blank (empty spaces)
- Text corruption or garbage characters
- Intermittent display issues

## Solution

Copy the data to arena allocator (frame-scoped) before passing to printSegment:

```zig
fn renderIcon(arena: std.mem.Allocator, win: vaxis.Window) !void {
    var icon_buf: [4]u8 = undefined;
    const icon_len = std.unicode.utf8Encode(icon_codepoint, &icon_buf) catch return;

    // Copy to arena - lifetime extends beyond printSegment
    const icon_text = try arena.dupe(u8, icon_buf[0..icon_len]);

    _ = win.printSegment(.{ .text = icon_text }, .{});
}
```

## When to Use

- Rendering text/icons built from stack buffers
- Any `printSegment` call with dynamically built strings
- When text appears blank but logic seems correct

## Diagnostic Steps

1. Terminal test: `echo -e "\xef\x81\xbb"` - if icon displays, terminal supports it
2. Add debug print before `printSegment` to verify buffer contents
3. Check if buffer is stack-local vs heap/arena allocated

## Key Insight

libvaxis uses deferred rendering - `printSegment` doesn't immediately write to terminal. It stores references to text segments and renders them all at once during `vx.render()`. Any stack-allocated data must outlive this render cycle.
