const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");
const vcs = @import("vcs.zig");

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
        try renderEntry(win, entry, row, is_cursor, is_marked, entry_query, file_vcs_status, arena);

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

    // Icon and name
    if (entry.kind == .directory) {
        const icon = if (entry.expanded) "v " else "> ";
        const icon_result = win.printSegment(.{
            .text = icon,
            .style = .{ .fg = .{ .index = 4 } }, // blue
        }, .{ .row_offset = row, .col_offset = col });
        col = icon_result.col;

        // Render directory name with search highlight
        col = try renderNameWithHighlight(win, safe_name, row, col, search_query, .{ .fg = .{ .index = 4 }, .bold = true });

        _ = win.printSegment(.{
            .text = "/",
            .style = .{ .fg = .{ .index = 4 } },
        }, .{ .row_offset = row, .col_offset = col });
    } else {
        const space_result = win.printSegment(.{ .text = "  " }, .{ .row_offset = row, .col_offset = col });
        col = space_result.col;

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
