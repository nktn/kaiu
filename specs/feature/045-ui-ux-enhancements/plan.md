# Implementation Plan: UI/UX Enhancements (Phase 3.5)

## Technical Context

- **Zig version**: 0.15.2+
- **TUI Library**: libvaxis (already handles mouse events for wheel scroll)
- **Target**: Ghostty (primary), Kitty, WezTerm

## Constitution Check

| Principle | Compliance | Notes |
|-----------|------------|-------|
| Target users | Yes | VSCode users expect mouse interaction |
| Familiarity | Yes | Mouse clicks match VSCode file explorer behavior |
| Vim-native | Yes | Does not replace Vim keybindings, adds mouse as alternative |
| Progressive disclosure | Yes | Mouse is optional, keyboard remains primary |
| No config required | Yes | Icons default on, `--no-icons` as opt-out |
| Quality standards | Yes | 50ms response time target for clicks |

## Architecture Overview

### Affected Modules

| Module | Changes | Reason |
|--------|---------|--------|
| `app.zig` | Major | Mouse click/double-click handling, new App state fields |
| `ui.zig` | Major | Status bar file info, Nerd Font icon rendering |
| `main.zig` | Minor | CLI flag `--no-icons` parsing |
| `tree.zig` | Minor | Stat info access for file size/mtime |
| `icons.zig` | New | Icon mapping data (extension to Unicode codepoint) |

### State Changes

No new `AppMode` states required. Mouse interactions happen within existing states:
- `tree_view`: Mouse click moves cursor, double-click expands/opens

**Note**: Preview mode mouse click is out of scope for Phase 3.5.

**New App fields**:
```zig
// Double-click detection (US2)
last_click_time: std.time.Instant,  // Monotonic timestamp of last left click
last_click_entry: ?usize,           // Visible index of last click (scroll-adjusted)

// CLI options (US4)
show_icons: bool,               // Default true, false with --no-icons

// Status bar cache (US3)
cached_file_info: ?CachedFileInfo,  // Cached stat info, updated on cursor change
```

### Memory Strategy

| Feature | Memory Approach | Rationale |
|---------|-----------------|-----------|
| Icon mapping | Comptime static | Icons are known at compile time, zero runtime allocation |
| File stat | On cursor change | Cache stat result, update only when cursor moves to different entry |
| Relative time | render_arena | Temporary strings freed each frame |
| Status bar text | render_arena | Per-frame allocation, reset on next render |

### Screen Layout Geometry

```
Row 0 to (height - 3): File tree area (clickable)
Row (height - 2):      Status bar line 1 (path + status message)
Row (height - 1):      Status bar line 2 (file info + help hint)
```

Click detection excludes the bottom 2 rows (status bar).

## Implementation Phases

### Phase 1: Mouse Click (US1 - P1)

**Technical approach**:

1. **Extend handleMouse()** to detect `button.left` release event
2. **Calculate visible index from screen row**:
   - `target_visible = click_row + scroll_offset`
   - Validate within file tree bounds
3. **Move cursor** to clicked entry using existing `moveCursor()` with delta

**Key implementation**:
```zig
fn handleMouse(self: *Self, mouse: vaxis.Mouse) void {
    // ... existing wheel handling ...

    // Left click in tree_view mode
    if (mouse.button == .left and mouse.type == .release) {
        if (self.mode == .tree_view or self.mode == .search) {
            self.handleLeftClick(mouse.row);
        }
    }
}

fn handleLeftClick(self: *Self, screen_row: u16) void {
    const ft = self.file_tree orelse return;

    // Calculate tree area (exclude status bar at bottom)
    const tree_height = self.vx.window().height -| 2; // 2 status bar lines
    if (screen_row >= tree_height) return; // Click on status bar, ignore

    // Convert screen row to visible index
    const target_visible = self.scroll_offset + screen_row;
    const visible_count = ft.countVisible(self.show_hidden);
    if (target_visible >= visible_count) return; // Click below last entry

    // Move cursor (reuse existing delta logic)
    const delta = @as(isize, @intCast(target_visible)) - @as(isize, @intCast(self.cursor));
    self.moveCursor(delta);
}
```

**FR coverage**: FR-001, FR-002, FR-003

**Risks**:
- Screen row calculation must account for scroll offset
- Status bar area must be excluded from click detection

---

### Phase 2: Double Click (US2 - P2)

**Depends on**: Phase 1

**Technical approach**:

1. **Track click state** with timestamp and row
2. **Detect double-click** when second click occurs within 400ms on same row
3. **Trigger action** based on entry type:
   - Directory: toggle expand (same as `Tab` or `l`/`h`)
   - File: open preview (same as `l`/`Enter`)

**Key implementation**:
```zig
// In App struct
last_click_time: ?std.time.Instant = null,
last_click_entry: ?usize = null,  // visible index (scroll-adjusted)

const double_click_threshold_ns: u64 = 400 * std.time.ns_per_ms;

fn handleLeftClick(self: *Self, screen_row: u16) void {
    // ... bounds checking from Phase 1 ...

    // Calculate visible index (scroll-adjusted entry identity)
    const target_visible = self.scroll_offset + screen_row;

    const now = std.time.Instant.now() catch return;
    const is_double_click = if (self.last_click_time) |last_time| blk: {
        const elapsed = now.since(last_time);
        break :blk self.last_click_entry == target_visible and
            elapsed <= double_click_threshold_ns;
    } else false;

    // Update click tracking (by entry identity, not screen row)
    self.last_click_time = now;
    self.last_click_entry = target_visible;

    if (is_double_click) {
        // Double-click: expand/collapse or preview
        self.handleDoubleClick();
    } else {
        // Single click: move cursor
        const delta = @as(isize, @intCast(target_visible)) - @as(isize, @intCast(self.cursor));
        self.moveCursor(delta);
    }
}

fn handleDoubleClick(self: *Self) !void {
    // Reuse existing expandOrEnter logic
    try self.expandOrEnter();
}
```

**FR coverage**: FR-010, FR-011, FR-012, FR-013

**Risks**:
- Must track both time and entry identity to avoid false positives
- Uses monotonic time (std.time.Instant) to avoid wall-clock drift issues
- Rapid clicking different entries should not trigger double-click

---

### Phase 3: Status Bar File Info (US3 - P2)

**Independent of**: Phase 1, 2

**Technical approach**:

1. **Cache stat on cursor change** - only call stat() when cursor moves to a different entry
2. **Format file size** with human-readable units (B, K, M, G)
3. **Format relative time** for mtime (just now, 5 min ago, yesterday, etc.)
4. **Update status bar layout** to show: `filename | size | modified`
5. **Handle stat failures** - show "-" for size/time when stat() fails

**Key implementation**:

```zig
// In ui.zig - new functions

/// Format bytes to human-readable size (B, K, M, G)
pub fn formatSize(arena: std.mem.Allocator, bytes: u64) ![]const u8 {
    if (bytes < 1024) {
        return std.fmt.allocPrint(arena, "{d}B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        return std.fmt.allocPrint(arena, "{d:.1}K", .{@as(f64, @floatFromInt(bytes)) / 1024.0});
    } else if (bytes < 1024 * 1024 * 1024) {
        return std.fmt.allocPrint(arena, "{d:.1}M", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0)});
    } else {
        return std.fmt.allocPrint(arena, "{d:.1}G", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0)});
    }
}

/// Format timestamp to relative time
pub fn formatRelativeTime(arena: std.mem.Allocator, mtime_sec: i128, now_sec: i64) ![]const u8 {
    const diff = now_sec - @as(i64, @intCast(mtime_sec));

    if (diff < 60) return "just now";
    if (diff < 3600) {
        const mins = @divFloor(diff, 60);
        return std.fmt.allocPrint(arena, "{d} min ago", .{mins});
    }
    if (diff < 86400) {
        const hours = @divFloor(diff, 3600);
        return std.fmt.allocPrint(arena, "{d} hr ago", .{hours});
    }
    if (diff < 86400 * 2) return "yesterday";
    if (diff < 86400 * 30) {
        const days = @divFloor(diff, 86400);
        return std.fmt.allocPrint(arena, "{d} days ago", .{days});
    }
    // Absolute date for older files
    // Use strftime-like format: "Jan 20" or "Jan 20 2025"
    // ...
}
```

**Status bar layout**:
```
Line 1: ~/path/to/dir | status_message
Line 2: filename.zig | 1.5K | 5 min ago       ?:help
```

For directories:
```
Line 2: dirname/ | 3 items                    ?:help
```

**FR coverage**: FR-020, FR-021, FR-022, FR-023, FR-024, FR-025, FR-026, FR-027

**Risks**:
- stat() is I/O; cache on cursor change, not on every render
- Mtime format uses epoch math (English format, no locale/timezone complexity)
- Handle stat failures gracefully (permission denied, broken symlinks)

---

### Phase 4: Nerd Font Icons (US4 - P3)

**Independent of**: Phase 1, 2, 3

**Technical approach**:

1. **Create icons.zig** module with static comptime mapping
2. **Map extensions to icons** using Nerd Font Unicode codepoints
3. **Handle special filenames** (Makefile, .gitignore, etc.)
4. **Add CLI flag** `--no-icons` in main.zig
5. **Modify renderEntry()** to prepend icon before filename

**icons.zig structure**:
```zig
pub const Icon = struct {
    codepoint: u21,
    color: ?u8, // ANSI color index, null for default
};

// Directory icons
pub const folder_closed = Icon{ .codepoint = 0xf07b, .color = 4 }; //
pub const folder_open = Icon{ .codepoint = 0xf07c, .color = 4 };   //

// Default file icon
pub const file_default = Icon{ .codepoint = 0xf15b, .color = null }; //

// Extension mapping (comptime)
pub const extension_icons = std.StaticStringMap(Icon).initComptime(.{
    .{ "zig", Icon{ .codepoint = 0xe6a9, .color = 3 } },    //
    .{ "md", Icon{ .codepoint = 0xe609, .color = 4 } },     //
    .{ "json", Icon{ .codepoint = 0xe60b, .color = 3 } },   //
    .{ "toml", Icon{ .codepoint = 0xe615, .color = 7 } },   //
    .{ "py", Icon{ .codepoint = 0xe606, .color = 3 } },     //
    .{ "js", Icon{ .codepoint = 0xe60c, .color = 3 } },     //
    .{ "ts", Icon{ .codepoint = 0xe628, .color = 4 } },     //
    .{ "rs", Icon{ .codepoint = 0xe7a8, .color = 1 } },     //
    .{ "go", Icon{ .codepoint = 0xe627, .color = 6 } },     //
    // ... 20+ more extensions
});

// Special filename mapping (comptime)
pub const filename_icons = std.StaticStringMap(Icon).initComptime(.{
    .{ "Makefile", Icon{ .codepoint = 0xe673, .color = 7 } },
    .{ ".gitignore", Icon{ .codepoint = 0xf1d3, .color = 1 } },
    .{ ".env", Icon{ .codepoint = 0xf462, .color = 3 } },
    .{ "LICENSE", Icon{ .codepoint = 0xe60a, .color = 3 } },
    .{ "README.md", Icon{ .codepoint = 0xe609, .color = 4 } },
    // ... more special files
});

pub fn getIcon(name: []const u8, is_dir: bool, is_expanded: bool) Icon {
    if (is_dir) {
        return if (is_expanded) folder_open else folder_closed;
    }

    // Check special filenames first
    if (filename_icons.get(name)) |icon| {
        return icon;
    }

    // Check extension
    if (std.mem.lastIndexOf(u8, name, '.')) |dot_idx| {
        const ext = name[dot_idx + 1 ..];
        if (extension_icons.get(ext)) |icon| {
            return icon;
        }
    }

    return file_default;
}
```

**CLI flag handling in main.zig**:
```zig
// Parse --no-icons flag
var show_icons = true;
var path_arg: ?[]const u8 = null;

for (args[1..]) |arg| {
    if (std.mem.eql(u8, arg, "--no-icons")) {
        show_icons = false;
    } else if (!std.mem.startsWith(u8, arg, "-")) {
        path_arg = arg;
    }
}

const raw_path = path_arg orelse ".";
// Pass show_icons to App
```

**FR coverage**: FR-030, FR-031, FR-032, FR-033, FR-034

**Risks**:
- Nerd Font not installed: Icons will show as replacement character
- No automatic detection possible; `--no-icons` is explicit opt-out
- Icon width handling: use vaxis `stringWidth()` for actual cell width measurement, not fixed 2-char assumption

---

## Key Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Double-click threshold | 300ms / 400ms / 500ms | 400ms | Standard OS default |
| Double-click timing | Wall clock / Monotonic | Monotonic (std.time.Instant) | Immune to NTP/time adjustments |
| Double-click target | Screen row / Entry identity | Entry identity (visible index) | Robust under scrolling |
| Icon module | Inline in ui.zig / Separate icons.zig | Separate | Better separation of concerns, easier to expand |
| Icon mapping | HashMap / StaticStringMap | StaticStringMap | Zero runtime allocation, comptime safety |
| Icon width | Fixed 2-char / Dynamic measurement | Dynamic (vaxis stringWidth) | Handles variable-width glyphs |
| Stat for status bar | Every render / On cursor change | On cursor change | Avoid I/O on every frame |
| --no-icons default | On / Off | On (icons enabled) | Modern terminals support Nerd Fonts |
| Nerd Font detection | Auto-detect / Manual flag | Manual (--no-icons) | No reliable detection method |

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Click detection off-by-one | Medium | Medium | Thorough testing with scroll offset |
| Status bar stat I/O latency | Low | Low | Cache on cursor change, not every render |
| Icon rendering breaks layout | Medium | Medium | Use vaxis stringWidth(), test without Nerd Font |
| Double-click false positives | Medium | Low | Track both monotonic time AND entry identity |
| Date formatting complexity | Low | Medium | Use simple epoch math, English format fixed |
| Scroll between clicks | Medium | Low | Track entry identity (visible index), not screen row |

## Test Strategy

### Unit Tests

- `formatSize()`: Edge cases (0B, 1K, 1M, 1G)
- `formatRelativeTime()`: just now, minutes, hours, days, months
- `getIcon()`: Extensions, special files, directories, fallback

### Integration Tests

- Mouse click at various scroll offsets
- Double-click timing edge cases
- Status bar with files, directories, special entries

### Manual Tests

- Click/double-click behavior in Ghostty, Kitty, WezTerm
- Icons with/without Nerd Font installed
- Status bar with various file sizes and dates
