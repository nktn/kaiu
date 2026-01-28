---
name: zig-static-string-map-icons
description: Compile-time zero-allocation icon lookup using StaticStringMap
---

# Compile-Time Icon Lookup with StaticStringMap

**Extracted:** 2026-01-28
**Context:** kaiu Phase 3.5 - US4 (Nerd Font icons)

## Problem

Mapping file extensions/names to icons requires:
1. Fast lookup (called for every visible entry on every frame)
2. Zero runtime allocation (TUI render loop must be allocation-free)
3. Easy to extend (add new file types)
4. Compile-time validation (catch typos early)

Naive approaches:
```zig
// HashMap - requires runtime allocation
var map = std.StringHashMap(Icon).init(allocator);
try map.put("zig", zig_icon); // Allocates!

// Linear search - O(n) lookup
fn getIcon(ext: []const u8) Icon {
    if (std.mem.eql(u8, ext, "zig")) return zig_icon;
    if (std.mem.eql(u8, ext, "md")) return md_icon;
    // ... 50+ comparisons
}
```

## Solution

Use `std.StaticStringMap` with `initComptime()`:

```zig
pub const Icon = struct {
    codepoint: u21,  // Nerd Font Unicode
    color: ?u8,      // ANSI color index
};

// Compile-time constant - no runtime allocation
pub const extension_icons = std.StaticStringMap(Icon).initComptime(.{
    // Programming languages
    .{ "zig", Icon{ .codepoint = 0xe6a9, .color = 3 } }, //
    .{ "py", Icon{ .codepoint = 0xe606, .color = 3 } },  //  (Python)
    .{ "js", Icon{ .codepoint = 0xe74e, .color = 3 } },  //  (JavaScript)
    .{ "rs", Icon{ .codepoint = 0xe7a8, .color = 1 } },  //  (Rust)
    .{ "go", Icon{ .codepoint = 0xe627, .color = 6 } },  //  (Go)

    // Data formats
    .{ "json", Icon{ .codepoint = 0xe60b, .color = 3 } }, //
    .{ "toml", Icon{ .codepoint = 0xe60b, .color = 7 } }, //
    .{ "yaml", Icon{ .codepoint = 0xe60b, .color = 1 } }, //

    // Images
    .{ "png", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "jpg", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "svg", Icon{ .codepoint = 0xf1c5, .color = 3 } }, //

    // ... 50+ total entries
});

// Special filenames (Makefile, .gitignore, etc.)
pub const filename_icons = std.StaticStringMap(Icon).initComptime(.{
    .{ "Makefile", Icon{ .codepoint = 0xe673, .color = 7 } }, //
    .{ ".gitignore", Icon{ .codepoint = 0xf1d3, .color = 1 } }, //
    .{ "Dockerfile", Icon{ .codepoint = 0xf308, .color = 4 } }, //
    .{ "build.zig", Icon{ .codepoint = 0xe6a9, .color = 3 } }, //
    // ... more special files
});
```

## Usage

```zig
pub fn getIcon(name: []const u8, is_dir: bool, is_expanded: bool) Icon {
    // Priority 1: Directory state
    if (is_dir) {
        return if (is_expanded) folder_open else folder_closed;
    }

    // Priority 2: Special filenames (exact match)
    if (filename_icons.get(name)) |icon| {
        return icon;
    }

    // Priority 3: Extension (case-insensitive)
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot_idx| {
        const ext = name[dot_idx + 1 ..];
        // Lowercase conversion (stack buffer, no allocation)
        var lower_buf: [16]u8 = undefined;
        if (ext.len <= lower_buf.len) {
            for (ext, 0..) |c, i| {
                lower_buf[i] = std.ascii.toLower(c);
            }
            const lower_ext = lower_buf[0..ext.len];
            if (extension_icons.get(lower_ext)) |icon| {
                return icon;
            }
        }
    }

    // Fallback: Default file icon
    return file_default;
}
```

## Why StaticStringMap?

### Compile-Time Construction

`initComptime()` builds the lookup table **at compile time**:
- Zero runtime cost for initialization
- No allocator needed
- Compiler catches duplicate keys

### Perfect Hashing

StaticStringMap uses a **perfect hash function** for the given keys:
- O(1) lookup (no collisions)
- Minimal memory overhead
- Generated at compile time

### Type Safety

Keys and values are type-checked at compile time:
```zig
.{ "zig", Icon{ .codepoint = 0xe6a9, .color = 3 } }, // OK
.{ "zig", 42 }, // Compile error: expected Icon, got comptime_int
```

## Performance Comparison

| Approach | Lookup Time | Memory | Allocation |
|----------|-------------|--------|------------|
| **StaticStringMap** | **O(1)** | **Optimal** | **Zero** |
| HashMap (runtime) | O(1) amortized | More (rehashing) | Required |
| Linear search | O(n) | Minimal | Zero |

**Render loop impact** (60 FPS, 30 visible entries):
- StaticStringMap: 1800 lookups/sec, zero allocation
- HashMap: 1800 lookups/sec, initial allocation at startup
- Linear search: 1800 × 50 comparisons/sec = 90,000 string comparisons

## Case-Insensitive Extension Matching

Extensions should match regardless of case (`README.MD` vs `readme.md`):

```zig
// Stack buffer for lowercase conversion (no allocation)
var lower_buf: [16]u8 = undefined;
if (ext.len <= lower_buf.len) {
    for (ext, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower_ext = lower_buf[0..ext.len];
    if (extension_icons.get(lower_ext)) |icon| {
        return icon;
    }
}
```

**Why 16-byte limit?**
- Extensions longer than 16 chars are rare
- Avoids heap allocation for common cases
- Falls through to default icon if too long

## Lookup Priority

Higher priority matches first:

1. **Directory state** → `folder_open` / `folder_closed`
2. **Special filenames** → `Makefile`, `.gitignore`, etc.
3. **Extensions** → `.zig`, `.py`, `.rs`, etc.
4. **Default fallback** → generic file icon

This allows `Makefile` (no extension) to get a custom icon, while `main.zig` uses extension-based lookup.

## Adding New Icons

To add a new file type:

```zig
pub const extension_icons = std.StaticStringMap(Icon).initComptime(.{
    // Existing entries...

    // Add new programming language
    .{ "kt", Icon{ .codepoint = 0xe634, .color = 5 } }, //  (Kotlin)
});
```

Compiler validates:
- No duplicate keys (compile error if `.kt` already exists)
- Type matches `Icon` struct
- Unicode codepoint is valid `u21`

## When to Use

This pattern applies when:
1. Mapping **strings** to **values** (icons, colors, configs)
2. Set of keys is **known at compile time** (not user input)
3. Lookup happens **frequently** (hot path)
4. **Zero allocation** is required (render loops, embedded systems)

## Alternatives Considered

1. **Runtime HashMap**:
   - Requires allocator
   - Initialization cost at startup
   - **Rejected**: Unnecessary allocation for static data

2. **Enum-based dispatch**:
   - Type-safe but requires manual parsing
   - More verbose for 50+ file types
   - **Rejected**: String → Enum conversion is extra work

3. **Perfect hash generator** (external tool):
   - More control over hash function
   - **Rejected**: StaticStringMap already does this at compile time

## Testing

```zig
test "extension lookup is case-insensitive" {
    const icon1 = getIcon("main.ZIG", false, false);
    const icon2 = getIcon("main.zig", false, false);
    try std.testing.expectEqual(icon1.codepoint, icon2.codepoint);
}

test "special filename takes priority over extension" {
    // Makefile has no extension but should get custom icon
    const icon = getIcon("Makefile", false, false);
    try std.testing.expect(icon.codepoint != file_default.codepoint);
}

test "unknown extension falls back to default" {
    const icon = getIcon("file.xyz999", false, false);
    try std.testing.expectEqual(file_default.codepoint, icon.codepoint);
}

test "at least 20 file types supported" {
    var count: usize = 0;
    const keys = extension_icons.keys();
    for (keys) |_| count += 1;
    try std.testing.expect(count >= 20);
}
```

## Unicode Codepoint Reference

Nerd Font icons use **Unicode Private Use Area**:
- U+E000 to U+F8FF: Private Use Area
- U+F0000 to U+10FFFF: Supplementary Private Use Areas

Example codepoints:
- 0xe6a9 = `` (Zig logo)
- 0xe606 = `` (Python logo)
- 0xf1d3 = `` (Git logo)
- 0xf07b = `` (Folder closed)
- 0xf07c = `` (Folder open)

## References

- kaiu: `src/icons.zig` - Icon definitions and lookup
- Zig std: `std.StaticStringMap` - [Documentation](https://ziglang.org/documentation/master/std/#A;std:StaticStringMap)
- Nerd Fonts: [Cheat Sheet](https://www.nerdfonts.com/cheat-sheet)
- Related pattern: `.claude/skills/learned/tui-status-bar-caching.md` (also render-loop optimized)
