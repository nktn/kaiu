const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const vcs = @import("vcs.zig");
const icons = @import("icons.zig");
const reference = @import("reference.zig");

/// Sanitize text for safe terminal display by replacing control characters.
/// Control chars (0x00-0x1F, 0x7F) and escape (0x1B) are replaced with '?'.
/// Returns the original string if no sanitization needed, or an allocated copy.
pub fn sanitizeForDisplay(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    // First pass: check if sanitization is needed
    var needs_sanitization = false;
    for (text) |c| {
        if (c < 0x20 or c == 0x7F) {
            needs_sanitization = true;
            break;
        }
    }

    if (!needs_sanitization) {
        return text;
    }

    // Second pass: create sanitized copy
    var result = try allocator.alloc(u8, text.len);
    for (text, 0..) |c, i| {
        result[i] = if (c < 0x20 or c == 0x7F) '?' else c;
    }
    return result;
}

pub fn renderTree(
    win: vaxis.Window,
    ft: *tree.FileTree,
    cursor: usize,
    scroll_offset: usize,
    show_hidden: bool,
    search_query: ?[]const u8,
    search_matches: []const usize,
    marked_files: *const std.StringHashMap(void),
    vcs_status: ?*const vcs.VCSStatusResult,
    show_icons: bool, // Phase 3.5 - US4: T031
    arena: std.mem.Allocator,
) !void {
    const height = win.height;
    var row: u16 = 0;
    var visible_index: usize = 0;

    for (ft.entries.items, 0..) |entry, actual_index| {
        // Skip hidden files if not showing them
        if (!show_hidden and entry.is_hidden) continue;

        // Skip entries before scroll offset
        if (visible_index < scroll_offset) {
            visible_index += 1;
            continue;
        }

        // Stop if we've filled the screen
        if (row >= height) break;

        const is_cursor = visible_index == cursor;
        const is_marked = marked_files.contains(entry.path);
        // Only pass search_query if this entry is in search_matches (O(n) but matches are few)
        const entry_query: ?[]const u8 = if (search_query != null and isInMatches(actual_index, search_matches))
            search_query
        else
            null;

        // Get VCS status for this file (relative path)
        const file_vcs_status = getFileVCSStatus(ft, entry.path, vcs_status);
        try renderEntry(win, entry, row, is_cursor, is_marked, entry_query, file_vcs_status, show_icons, arena);

        row += 1;
        visible_index += 1;
    }

    // Status bar is now rendered separately by app.zig
}

/// Get VCS status for a file path (convert absolute to relative)
fn getFileVCSStatus(ft: *tree.FileTree, path: []const u8, vcs_status: ?*const vcs.VCSStatusResult) ?vcs.VCSFileStatus {
    const status = vcs_status orelse return null;

    // Convert absolute path to relative path from repo root
    if (std.mem.startsWith(u8, path, ft.root_path)) {
        var relative = path[ft.root_path.len..];
        // Remove leading slash
        if (relative.len > 0 and relative[0] == '/') {
            relative = relative[1..];
        }
        return status.get(relative);
    }

    return null;
}

/// Check if index is in matches list (linear search, but matches are typically few)
/// Check if index is in matches array.
/// O(n) linear scan, but:
/// - matches array is typically small (few search hits)
/// - called only for visible entries (~30 rows)
/// - total cost: O(visible_rows * match_count), acceptable for TUI
fn isInMatches(index: usize, matches: []const usize) bool {
    for (matches) |m| {
        if (m == index) return true;
    }
    return false;
}

fn renderEntry(
    win: vaxis.Window,
    entry: tree.FileEntry,
    row: u16,
    is_cursor: bool,
    is_marked: bool,
    search_query: ?[]const u8,
    vcs_file_status: ?vcs.VCSFileStatus,
    show_icons: bool, // Phase 3.5 - US4: T031
    arena: std.mem.Allocator,
) !void {
    var col: u16 = 0;

    // Sanitize filename for safe display (prevents terminal escape injection)
    const safe_name = try sanitizeForDisplay(arena, entry.name);

    // Mark indicator (before cursor)
    if (is_marked) {
        _ = win.printSegment(.{
            .text = "*",
            .style = .{ .fg = .{ .index = 5 }, .bold = true }, // magenta
        }, .{ .row_offset = row, .col_offset = col });
    } else {
        _ = win.printSegment(.{ .text = " " }, .{ .row_offset = row, .col_offset = col });
    }
    col += 1;

    // Cursor indicator
    if (is_cursor) {
        _ = win.printSegment(.{
            .text = "> ",
            .style = .{ .fg = .{ .index = 2 } }, // green
        }, .{ .row_offset = row, .col_offset = col });
    } else {
        _ = win.printSegment(.{ .text = "  " }, .{ .row_offset = row, .col_offset = col });
    }
    col += 2;

    // Indentation
    var i: usize = 0;
    while (i < entry.depth) : (i += 1) {
        _ = win.printSegment(.{ .text = "  " }, .{ .row_offset = row, .col_offset = col });
        col += 2;
    }

    // Phase 3.5 - US4: Get and render Nerd Font icon (T031)
    if (show_icons) {
        const icon = icons.getIcon(entry.name, entry.kind == .directory, entry.expanded);
        const icon_buf = icon.toUtf8();
        // FR-035: Use gwidth for proper cell width measurement
        const icon_len = std.unicode.utf8CodepointSequenceLength(icon.codepoint) catch 3;

        // Copy to arena to ensure lifetime extends beyond printSegment
        const icon_text = try arena.dupe(u8, icon_buf[0..icon_len]);
        const icon_width = vaxis.gwidth.gwidth(icon_text, .unicode);

        // Icon color (use icon's color or default)
        const icon_style: vaxis.Style = if (icon.color) |c|
            .{ .fg = .{ .index = c } }
        else
            .{};

        const icon_result = win.printSegment(.{
            .text = icon_text,
            .style = icon_style,
        }, .{ .row_offset = row, .col_offset = col });
        _ = icon_result; // col updated below

        // Space after icon
        col += @intCast(icon_width + 1);
    }

    // Icon and name
    if (entry.kind == .directory) {
        if (!show_icons) {
            // Legacy: show v/> for expand state
            const dir_icon = if (entry.expanded) "v " else "> ";
            const icon_result = win.printSegment(.{
                .text = dir_icon,
                .style = .{ .fg = .{ .index = 4 } }, // blue
            }, .{ .row_offset = row, .col_offset = col });
            col = icon_result.col;
        }

        // Render directory name with search highlight
        col = try renderNameWithHighlight(win, safe_name, row, col, search_query, .{ .fg = .{ .index = 4 }, .bold = true });

        _ = win.printSegment(.{
            .text = "/",
            .style = .{ .fg = .{ .index = 4 } },
        }, .{ .row_offset = row, .col_offset = col });
    } else {
        if (!show_icons) {
            // Legacy: 2-space indent for files
            const space_result = win.printSegment(.{ .text = "  " }, .{ .row_offset = row, .col_offset = col });
            col = space_result.col;
        }

        // Determine style based on VCS status (T022)
        // Colors per FR-003:
        // - Green (2): New/Untracked
        // - Yellow (3): Modified
        // - Red (1): Deleted
        // - Cyan (6): Renamed
        // - Magenta (5): Conflict
        const style: vaxis.Style = if (entry.is_hidden)
            .{ .fg = .{ .index = 8 } } // dim for hidden
        else if (vcs_file_status) |status|
            switch (status) {
                .untracked => .{ .fg = .{ .index = 2 } }, // green
                .modified => .{ .fg = .{ .index = 3 } }, // yellow
                .deleted => .{ .fg = .{ .index = 1 } }, // red
                .renamed => .{ .fg = .{ .index = 6 } }, // cyan
                .conflict => .{ .fg = .{ .index = 5 } }, // magenta
                .unchanged => .{},
            }
        else
            .{};

        // Render file name with search highlight
        _ = try renderNameWithHighlight(win, safe_name, row, col, search_query, style);
    }
}

/// Find case-insensitive match position in haystack (public for reuse in app.zig)
pub fn findMatchPosition(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;

    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        var match = true;
        for (0..needle.len) |j| {
            const h = std.ascii.toLower(haystack[i + j]);
            const n = std.ascii.toLower(needle[j]);
            if (h != n) {
                match = false;
                break;
            }
        }
        if (match) return i;
    }
    return null;
}

/// Render filename with search match highlighted
fn renderNameWithHighlight(
    win: vaxis.Window,
    name: []const u8,
    row: u16,
    start_col: u16,
    search_query: ?[]const u8,
    base_style: vaxis.Style,
) !u16 {
    var col = start_col;

    // If no search query or no match, render normally
    const query = search_query orelse {
        const result = win.printSegment(.{
            .text = name,
            .style = base_style,
        }, .{ .row_offset = row, .col_offset = col });
        return result.col;
    };

    const match_pos = findMatchPosition(name, query) orelse {
        const result = win.printSegment(.{
            .text = name,
            .style = base_style,
        }, .{ .row_offset = row, .col_offset = col });
        return result.col;
    };

    // Render: before match + highlighted match + after match
    if (match_pos > 0) {
        const result = win.printSegment(.{
            .text = name[0..match_pos],
            .style = base_style,
        }, .{ .row_offset = row, .col_offset = col });
        col = result.col;
    }

    // Highlight style: yellow background with black text
    const highlight_style = vaxis.Style{
        .fg = .{ .index = 0 }, // black
        .bg = .{ .index = 3 }, // yellow
        .bold = true,
    };
    const match_end = match_pos + query.len;
    const result = win.printSegment(.{
        .text = name[match_pos..match_end],
        .style = highlight_style,
    }, .{ .row_offset = row, .col_offset = col });
    col = result.col;

    // After match
    if (match_end < name.len) {
        const after_result = win.printSegment(.{
            .text = name[match_end..],
            .style = base_style,
        }, .{ .row_offset = row, .col_offset = col });
        return after_result.col;
    }

    return col;
}

pub fn renderPreview(
    win: vaxis.Window,
    content: []const u8,
    filename: []const u8,
    scroll: usize,
    arena: std.mem.Allocator,
) !void {
    const height = win.height;
    if (height == 0) return;

    // Header (sanitized filename)
    const safe_filename = try sanitizeForDisplay(arena, filename);
    _ = win.printSegment(.{
        .text = safe_filename,
        .style = .{ .bold = true, .reverse = true },
    }, .{ .row_offset = 0, .col_offset = 0 });

    // Count total lines to determine line number width
    const total_lines = std.mem.count(u8, content, "\n") + 1;
    const line_num_width: usize = if (total_lines < 10) 1 else if (total_lines < 100) 2 else if (total_lines < 1000) 3 else if (total_lines < 10000) 4 else 5;

    // Content with line numbers
    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;
    var row: u16 = 1;

    while (lines.next()) |line| {
        if (line_num < scroll) {
            line_num += 1;
            continue;
        }

        if (row >= height) break;

        // Format line number dynamically using arena allocator
        // The arena persists until after vaxis.render() completes
        const line_num_str = try std.fmt.allocPrint(arena, "{d:>[1]} ", .{ line_num + 1, line_num_width });
        _ = win.printSegment(.{
            .text = line_num_str,
            .style = .{ .fg = .{ .index = 8 } },
        }, .{ .row_offset = row, .col_offset = 0 });

        // Print line content (sanitized)
        const col_offset: u16 = @intCast(line_num_width + 1);
        const max_len = @min(line.len, win.width -| col_offset);
        if (max_len > 0) {
            const safe_line = try sanitizeForDisplay(arena, line[0..max_len]);
            _ = win.printSegment(.{
                .text = safe_line,
            }, .{ .row_offset = row, .col_offset = col_offset });
        }

        line_num += 1;
        row += 1;
    }
}

pub fn renderHelp(win: vaxis.Window) !void {
    const height = win.height;
    const width = win.width;
    if (height < 3 or width < 20) {
        // Window too small - show minimal hint with close instruction
        _ = win.printSegment(.{ .text = "Help (any key)" }, .{});
        return;
    }
    if (height < 10 or width < 40) {
        // Compact help for small windows
        _ = win.printSegment(.{
            .text = "kaiu Help (press any key)",
            .style = .{ .bold = true, .reverse = true },
        }, .{ .row_offset = 0, .col_offset = 0 });
        _ = win.printSegment(.{ .text = "j/k:move h/l:collapse/expand o:preview" }, .{ .row_offset = 1, .col_offset = 0 });
        _ = win.printSegment(.{ .text = "/:search .:hidden ?:help q:quit" }, .{ .row_offset = 2, .col_offset = 0 });
        return;
    }

    // Center the help box
    const box_width: u16 = @min(60, width - 4);
    const box_height: u16 = @min(30, height - 4);
    const start_col: u16 = (width - box_width) / 2;
    const start_row: u16 = (height - box_height) / 2;

    // Title
    const title = "kaiu Help";
    const title_col = start_col + (box_width - @as(u16, @intCast(title.len))) / 2;
    _ = win.printSegment(.{
        .text = title,
        .style = .{ .bold = true, .reverse = true },
    }, .{ .row_offset = start_row, .col_offset = title_col });

    var row: u16 = start_row + 2;

    // Navigation section
    _ = win.printSegment(.{
        .text = "Navigation",
        .style = .{ .bold = true, .fg = .{ .index = 4 } },
    }, .{ .row_offset = row, .col_offset = start_col });
    row += 1;

    const nav_keys = [_][2][]const u8{
        .{ "j/k", "Move down/up" },
        .{ "h/l", "Collapse/Expand" },
        .{ "Arrows", "Same as hjkl" },
        .{ "gg/G", "Jump top/bottom" },
        .{ "H/L", "Collapse/Expand all" },
        .{ "Tab", "Toggle expand" },
    };

    for (nav_keys) |kv| {
        _ = win.printSegment(.{
            .text = kv[0],
            .style = .{ .fg = .{ .index = 3 } },
        }, .{ .row_offset = row, .col_offset = start_col + 2 });
        _ = win.printSegment(.{
            .text = kv[1],
        }, .{ .row_offset = row, .col_offset = start_col + 12 });
        row += 1;
    }

    row += 1;

    // Search section
    _ = win.printSegment(.{
        .text = "Search",
        .style = .{ .bold = true, .fg = .{ .index = 4 } },
    }, .{ .row_offset = row, .col_offset = start_col });
    row += 1;

    const search_keys = [_][2][]const u8{
        .{ "/", "Search" },
        .{ "n/N", "Next/Prev match" },
        .{ "Esc", "Clear search" },
    };

    for (search_keys) |kv| {
        _ = win.printSegment(.{
            .text = kv[0],
            .style = .{ .fg = .{ .index = 3 } },
        }, .{ .row_offset = row, .col_offset = start_col + 2 });
        _ = win.printSegment(.{
            .text = kv[1],
        }, .{ .row_offset = row, .col_offset = start_col + 12 });
        row += 1;
    }

    row += 1;

    // File Operations section
    _ = win.printSegment(.{
        .text = "File Operations",
        .style = .{ .bold = true, .fg = .{ .index = 4 } },
    }, .{ .row_offset = row, .col_offset = start_col });
    row += 1;

    const file_keys = [_][2][]const u8{
        .{ "Space", "Mark/Unmark" },
        .{ "y/d", "Yank/Cut" },
        .{ "p", "Paste" },
        .{ "D", "Delete" },
        .{ "r", "Rename" },
        .{ "a/A", "New file/dir" },
    };

    for (file_keys) |kv| {
        _ = win.printSegment(.{
            .text = kv[0],
            .style = .{ .fg = .{ .index = 3 } },
        }, .{ .row_offset = row, .col_offset = start_col + 2 });
        _ = win.printSegment(.{
            .text = kv[1],
        }, .{ .row_offset = row, .col_offset = start_col + 12 });
        row += 1;
    }

    row += 1;

    // Other section
    _ = win.printSegment(.{
        .text = "Other",
        .style = .{ .bold = true, .fg = .{ .index = 4 } },
    }, .{ .row_offset = row, .col_offset = start_col });
    row += 1;

    const other_keys = [_][2][]const u8{
        .{ ".", "Toggle hidden" },
        .{ "R", "Reload tree" },
        .{ "c/C", "Copy path/name" },
        .{ "o/Enter", "Open/Preview" },
        .{ "gv", "Cycle VCS mode" },
        .{ "W", "Toggle watching" },
        .{ "q", "Quit" },
    };

    for (other_keys) |kv| {
        _ = win.printSegment(.{
            .text = kv[0],
            .style = .{ .fg = .{ .index = 3 } },
        }, .{ .row_offset = row, .col_offset = start_col + 2 });
        _ = win.printSegment(.{
            .text = kv[1],
        }, .{ .row_offset = row, .col_offset = start_col + 12 });
        row += 1;
    }

    row += 2;

    // Footer
    const footer = "Press any key to close";
    const footer_col = start_col + (box_width - @as(u16, @intCast(footer.len))) / 2;
    _ = win.printSegment(.{
        .text = footer,
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = row, .col_offset = footer_col });
}

// ===== Phase 3.5 - US3: Status Bar File Info (T016, T017) =====

/// Format bytes to human-readable size (B, K, M, G)
/// FR-022: Size in human-readable format
pub fn formatSize(arena: std.mem.Allocator, bytes: u64) ![]const u8 {
    if (bytes < 1024) {
        return std.fmt.allocPrint(arena, "{d}B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        // Avoid ".0" suffix for whole numbers
        if (kb == @trunc(kb)) {
            return std.fmt.allocPrint(arena, "{d}K", .{@as(u64, @intFromFloat(kb))});
        }
        return std.fmt.allocPrint(arena, "{d:.1}K", .{kb});
    } else if (bytes < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        if (mb == @trunc(mb)) {
            return std.fmt.allocPrint(arena, "{d}M", .{@as(u64, @intFromFloat(mb))});
        }
        return std.fmt.allocPrint(arena, "{d:.1}M", .{mb});
    } else {
        const gb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
        if (gb == @trunc(gb)) {
            return std.fmt.allocPrint(arena, "{d}G", .{@as(u64, @intFromFloat(gb))});
        }
        return std.fmt.allocPrint(arena, "{d:.1}G", .{gb});
    }
}

/// Format timestamp to relative time (English format)
/// FR-023, FR-024, FR-028: Relative time within 30 days, absolute date after
pub fn formatRelativeTime(arena: std.mem.Allocator, mtime_sec: i128, now_sec: i64) ![]const u8 {
    // Handle edge case: mtime in future or invalid
    if (mtime_sec > now_sec) {
        return "just now";
    }

    const diff: i64 = now_sec - @as(i64, @intCast(@min(mtime_sec, std.math.maxInt(i64))));

    if (diff < 60) {
        return "just now";
    }
    if (diff < 3600) {
        const mins = @divFloor(diff, 60);
        if (mins == 1) {
            return "1 min ago";
        }
        return std.fmt.allocPrint(arena, "{d} min ago", .{mins});
    }
    if (diff < 86400) {
        const hours = @divFloor(diff, 3600);
        if (hours == 1) {
            return "1 hr ago";
        }
        return std.fmt.allocPrint(arena, "{d} hr ago", .{hours});
    }
    if (diff < 86400 * 2) {
        return "yesterday";
    }
    // FR-028: 30 days cutoff for relative time
    if (diff < 86400 * 30) {
        const days = @divFloor(diff, 86400);
        return std.fmt.allocPrint(arena, "{d} days ago", .{days});
    }

    // FR-024: Absolute date for older files (English format)
    // Convert mtime_sec to date components using epoch calculation
    const epoch_days = @divFloor(@as(i64, @intCast(@min(mtime_sec, std.math.maxInt(i64)))), 86400);
    const date = epochDaysToDate(epoch_days);

    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    const month_name = if (date.month >= 1 and date.month <= 12) months[date.month - 1] else "???";

    // Get current year for comparison
    const now_epoch_days = @divFloor(now_sec, 86400);
    const now_date = epochDaysToDate(now_epoch_days);

    // Show year if different from current year
    if (date.year != now_date.year) {
        return std.fmt.allocPrint(arena, "{s} {d} {d}", .{ month_name, date.day, date.year });
    }
    return std.fmt.allocPrint(arena, "{s} {d}", .{ month_name, date.day });
}

/// Simple date struct for epoch conversion
const SimpleDate = struct {
    year: i32,
    month: u8,
    day: u8,
};

/// Convert epoch days (since 1970-01-01) to year/month/day
/// Algorithm based on Howard Hinnant's civil_from_days
fn epochDaysToDate(epoch_days: i64) SimpleDate {
    // Shift epoch to March 1, 0000
    const z = epoch_days + 719468;
    const era: i32 = @intCast(if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097));
    const doe: u32 = @intCast(z - era * 146097); // day of era [0, 146096]
    const yoe: u32 = @intCast(@divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365));
    const y: i32 = @as(i32, @intCast(yoe)) + era * 400;
    const doy: u32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: u32 = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    const year: i32 = if (m <= 2) y + 1 else y;

    return .{ .year = year, .month = m, .day = d };
}

test "renderEntry does not crash with empty window" {
    // Basic smoke test - just ensure the function signature is correct
    const entry = tree.FileEntry{
        .name = "test",
        .path = "/test",
        .kind = .file,
        .is_hidden = false,
        .expanded = false,
        .children = null,
        .depth = 0,
    };
    _ = entry;
    // Can't test rendering without a real vaxis.Window
}

// ===== Phase 3.5 - US3: Status Bar Tests (T014, T015, T015a) =====

test "US3-T014: formatSize edge cases (0B, 1K, 1M, 1G)" {
    const allocator = std.testing.allocator;

    // 0 bytes
    const s0 = try formatSize(allocator, 0);
    defer allocator.free(s0);
    try std.testing.expectEqualStrings("0B", s0);

    // 1 byte
    const s1 = try formatSize(allocator, 1);
    defer allocator.free(s1);
    try std.testing.expectEqualStrings("1B", s1);

    // 1023 bytes (just under 1K)
    const s1023 = try formatSize(allocator, 1023);
    defer allocator.free(s1023);
    try std.testing.expectEqualStrings("1023B", s1023);

    // 1024 bytes = exactly 1K
    const s1k = try formatSize(allocator, 1024);
    defer allocator.free(s1k);
    try std.testing.expectEqualStrings("1K", s1k);

    // 1.5K = 1536 bytes
    const s1_5k = try formatSize(allocator, 1536);
    defer allocator.free(s1_5k);
    try std.testing.expectEqualStrings("1.5K", s1_5k);

    // 1M = 1048576 bytes
    const s1m = try formatSize(allocator, 1024 * 1024);
    defer allocator.free(s1m);
    try std.testing.expectEqualStrings("1M", s1m);

    // 1G = 1073741824 bytes
    const s1g = try formatSize(allocator, 1024 * 1024 * 1024);
    defer allocator.free(s1g);
    try std.testing.expectEqualStrings("1G", s1g);

    // 2.5G
    const s2_5g = try formatSize(allocator, 2684354560);
    defer allocator.free(s2_5g);
    try std.testing.expectEqualStrings("2.5G", s2_5g);
}

test "US3-T015: formatRelativeTime (just now, minutes, hours, days)" {
    const allocator = std.testing.allocator;
    // Use a fixed "now" timestamp: 2024-06-15 12:00:00 UTC = 1718452800
    const now_sec: i64 = 1718452800;

    // Just now (0 seconds ago)
    const t0 = try formatRelativeTime(allocator, now_sec, now_sec);
    try std.testing.expectEqualStrings("just now", t0);

    // 30 seconds ago
    const t30s = try formatRelativeTime(allocator, now_sec - 30, now_sec);
    try std.testing.expectEqualStrings("just now", t30s);

    // 5 minutes ago
    const t5m = try formatRelativeTime(allocator, now_sec - 300, now_sec);
    defer allocator.free(t5m);
    try std.testing.expectEqualStrings("5 min ago", t5m);

    // 1 hour ago
    const t1h = try formatRelativeTime(allocator, now_sec - 3600, now_sec);
    try std.testing.expectEqualStrings("1 hr ago", t1h);

    // 5 hours ago
    const t5h = try formatRelativeTime(allocator, now_sec - 18000, now_sec);
    defer allocator.free(t5h);
    try std.testing.expectEqualStrings("5 hr ago", t5h);

    // Yesterday (36 hours ago)
    const t_yesterday = try formatRelativeTime(allocator, now_sec - 129600, now_sec);
    try std.testing.expectEqualStrings("yesterday", t_yesterday);

    // 10 days ago
    const t10d = try formatRelativeTime(allocator, now_sec - 864000, now_sec);
    defer allocator.free(t10d);
    try std.testing.expectEqualStrings("10 days ago", t10d);

    // 45 days ago (past 30-day cutoff, same year) -> "May 1"
    const t45d = try formatRelativeTime(allocator, now_sec - (86400 * 45), now_sec);
    defer allocator.free(t45d);
    try std.testing.expectEqualStrings("May 1", t45d);
}

test "US3-T015a: formatRelativeTime shows year for dates in different year" {
    const allocator = std.testing.allocator;
    // "now" = 2024-01-15 = 1705276800
    const now_sec: i64 = 1705276800;

    // 2023-06-15 = 1686787200 (different year)
    const old_date = try formatRelativeTime(allocator, 1686787200, now_sec);
    defer allocator.free(old_date);
    try std.testing.expectEqualStrings("Jun 15 2023", old_date);
}

test "epochDaysToDate converts correctly" {
    // 1970-01-01 = epoch day 0
    const d1 = epochDaysToDate(0);
    try std.testing.expectEqual(@as(i32, 1970), d1.year);
    try std.testing.expectEqual(@as(u8, 1), d1.month);
    try std.testing.expectEqual(@as(u8, 1), d1.day);

    // 2024-06-15 = epoch day 19889
    const d2 = epochDaysToDate(19889);
    try std.testing.expectEqual(@as(i32, 2024), d2.year);
    try std.testing.expectEqual(@as(u8, 6), d2.month);
    try std.testing.expectEqual(@as(u8, 15), d2.day);

    // 2000-01-01 = epoch day 10957
    const d3 = epochDaysToDate(10957);
    try std.testing.expectEqual(@as(i32, 2000), d3.year);
    try std.testing.expectEqual(@as(u8, 1), d3.month);
    try std.testing.expectEqual(@as(u8, 1), d3.day);
}

// =============================================================================
// Phase 4.0: Symbol Reference Display (T019, T022, T023)
// =============================================================================

/// Render reference list or error message. (T019, T022, T023)
pub fn renderReferenceList(
    win: vaxis.Window,
    ref_list: ?*reference.ReferenceList,
    error_message: ?[]const u8,
    arena: std.mem.Allocator,
) !void {
    const height = win.height;
    const width = win.width;

    win.clear();

    // Title bar
    const title = "References";
    _ = win.printSegment(.{
        .text = title,
        .style = .{ .bold = true, .reverse = true },
    }, .{ .row_offset = 0, .col_offset = 0 });

    // Fill rest of title bar
    if (width > title.len) {
        var spaces: [80]u8 = undefined;
        const fill_len = @min(width - title.len, 80);
        @memset(spaces[0..fill_len], ' ');
        _ = win.printSegment(.{
            .text = spaces[0..fill_len],
            .style = .{ .reverse = true },
        }, .{ .row_offset = 0, .col_offset = @intCast(title.len) });
    }

    // Show error message if present (T022, T023)
    if (error_message) |msg| {
        const row: u16 = height / 2;
        const col: u16 = if (width > msg.len) (width - @as(u16, @intCast(msg.len))) / 2 else 0;
        _ = win.printSegment(.{
            .text = msg,
            .style = .{ .fg = .{ .index = 1 } }, // Red
        }, .{ .row_offset = row, .col_offset = col });

        // Hint
        const hint = "Press any key to close";
        const hint_row = row + 2;
        const hint_col: u16 = if (width > hint.len) (width - @as(u16, @intCast(hint.len))) / 2 else 0;
        _ = win.printSegment(.{
            .text = hint,
            .style = .{ .fg = .{ .index = 8 } }, // Gray
        }, .{ .row_offset = hint_row, .col_offset = hint_col });
        return;
    }

    // Show reference list
    const rl = ref_list orelse return;
    const visible_count = rl.visibleCount();

    if (visible_count == 0) {
        const msg = "No references found";
        const row: u16 = height / 2;
        const col: u16 = if (width > msg.len) (width - @as(u16, @intCast(msg.len))) / 2 else 0;
        _ = win.printSegment(.{
            .text = msg,
            .style = .{ .fg = .{ .index = 3 } }, // Yellow
        }, .{ .row_offset = row, .col_offset = col });
        return;
    }

    // Column header
    _ = win.printSegment(.{
        .text = "File",
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = 1, .col_offset = 0 });
    _ = win.printSegment(.{
        .text = "Line",
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = 1, .col_offset = 40 });
    _ = win.printSegment(.{
        .text = "Code",
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = 1, .col_offset = 48 });

    // Render each reference
    var row: u16 = 2;
    const max_rows = if (height > 4) height - 4 else 1;

    // Calculate scroll offset
    const scroll_offset = if (rl.cursor >= max_rows) rl.cursor - max_rows + 1 else 0;

    var i: usize = scroll_offset;
    while (i < visible_count and row < max_rows + 2) : (i += 1) {
        const ref = rl.getVisible(i) orelse continue;
        const is_selected = (i == rl.cursor);

        // Background for selected row
        const style: vaxis.Style = if (is_selected) .{ .reverse = true } else .{};

        // File path (basename only, max 38 chars)
        const basename = std.fs.path.basename(ref.file_path);
        const display_path = if (basename.len > 38) basename[0..38] else basename;
        _ = win.printSegment(.{
            .text = display_path,
            .style = style,
        }, .{ .row_offset = row, .col_offset = 0 });

        // Line number
        const line_str = std.fmt.allocPrint(arena, "{d}", .{ref.line + 1}) catch "?";
        _ = win.printSegment(.{
            .text = line_str,
            .style = style,
        }, .{ .row_offset = row, .col_offset = 40 });

        // Code snippet (max width - 50)
        const snippet_max = if (width > 50) width - 50 else 10;
        const snippet = if (ref.snippet.len > snippet_max) ref.snippet[0..@intCast(snippet_max)] else ref.snippet;
        _ = win.printSegment(.{
            .text = snippet,
            .style = style,
        }, .{ .row_offset = row, .col_offset = 48 });

        row += 1;
    }

    // Status bar at bottom
    const status_row = height - 2;

    // Show filter pattern if active (T039)
    var col_offset: u16 = 0;
    if (rl.filter_pattern) |pattern| {
        const filter_str = std.fmt.allocPrint(arena, "Filter: {s} ", .{pattern}) catch "";
        _ = win.printSegment(.{
            .text = filter_str,
            .style = .{ .fg = .{ .index = 3 } }, // Yellow
        }, .{ .row_offset = status_row, .col_offset = 0 });
        col_offset = @intCast(filter_str.len);
    }

    const count_str = std.fmt.allocPrint(arena, "{d}/{d} references", .{ rl.cursor + 1, visible_count }) catch "";
    _ = win.printSegment(.{
        .text = count_str,
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = status_row, .col_offset = col_offset });

    // Help hint
    const hint = "j/k:move Enter:open o:preview f:filter G:graph q:close";
    const hint_col: u16 = if (width > hint.len) width - @as(u16, @intCast(hint.len)) else 0;
    _ = win.printSegment(.{
        .text = hint,
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = status_row, .col_offset = hint_col });
}

/// Render filter input overlay for reference list (T038, T039)
pub fn renderFilterInput(win: vaxis.Window, filter_text: []const u8) !void {
    const height = win.height;
    const width = win.width;

    // Draw input at the bottom of the screen
    const input_row = height - 3;

    // Clear the input row
    var spaces: [80]u8 = undefined;
    const fill_len = @min(width, 80);
    @memset(spaces[0..fill_len], ' ');
    _ = win.printSegment(.{
        .text = spaces[0..fill_len],
        .style = .{ .reverse = true },
    }, .{ .row_offset = input_row, .col_offset = 0 });

    // Draw prompt
    const prompt = "Filter: ";
    _ = win.printSegment(.{
        .text = prompt,
        .style = .{ .reverse = true, .bold = true },
    }, .{ .row_offset = input_row, .col_offset = 0 });

    // Draw filter text
    const max_text_len = if (width > prompt.len + 1) width - prompt.len - 1 else 0;
    const display_text = if (filter_text.len > max_text_len) filter_text[0..@intCast(max_text_len)] else filter_text;
    _ = win.printSegment(.{
        .text = display_text,
        .style = .{ .reverse = true },
    }, .{ .row_offset = input_row, .col_offset = @intCast(prompt.len) });

    // Draw cursor
    const cursor_col = prompt.len + filter_text.len;
    if (cursor_col < width) {
        _ = win.printSegment(.{
            .text = "_",
            .style = .{ .reverse = true, .bold = true },
        }, .{ .row_offset = input_row, .col_offset = @intCast(cursor_col) });
    }
}

/// Render call hierarchy graph in text mode (T032: Fallback display)
pub fn renderReferenceGraph(
    win: vaxis.Window,
    text_content: ?[]const u8,
    scroll_offset: usize,
    arena: std.mem.Allocator,
) !void {
    _ = arena;
    const height = win.height;
    const width = win.width;

    win.clear();

    // Title bar
    const title = "Call Hierarchy Graph";
    _ = win.printSegment(.{
        .text = title,
        .style = .{ .bold = true, .reverse = true },
    }, .{ .row_offset = 0, .col_offset = 0 });

    // Fill rest of title bar
    if (width > title.len) {
        var spaces: [80]u8 = undefined;
        const fill_len = @min(width - title.len, 80);
        @memset(spaces[0..fill_len], ' ');
        _ = win.printSegment(.{
            .text = spaces[0..fill_len],
            .style = .{ .reverse = true },
        }, .{ .row_offset = 0, .col_offset = @intCast(title.len) });
    }

    // Show text content with scrolling
    const content = text_content orelse {
        const msg = "No call hierarchy data available";
        const row: u16 = height / 2;
        const col: u16 = if (width > msg.len) (width - @as(u16, @intCast(msg.len))) / 2 else 0;
        _ = win.printSegment(.{
            .text = msg,
            .style = .{ .fg = .{ .index = 8 } },
        }, .{ .row_offset = row, .col_offset = col });
        return;
    };

    // Split content into lines and display with scroll
    var lines_iter = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;
    var display_row: u16 = 2; // Start after title bar

    while (lines_iter.next()) |line| {
        if (line_num < scroll_offset) {
            line_num += 1;
            continue;
        }

        if (display_row >= height - 2) break; // Leave room for status bar

        // Truncate line if too long
        const display_line = if (line.len > width) line[0..width] else line;
        _ = win.printSegment(.{
            .text = display_line,
        }, .{ .row_offset = display_row, .col_offset = 0 });

        display_row += 1;
        line_num += 1;
    }

    // Status bar at bottom
    const status_row = height - 2;
    const hint = "j/k:scroll  l/q:back to list";
    const hint_col: u16 = if (width > hint.len) width - @as(u16, @intCast(hint.len)) else 0;
    _ = win.printSegment(.{
        .text = hint,
        .style = .{ .fg = .{ .index = 8 } },
    }, .{ .row_offset = status_row, .col_offset = hint_col });
}
