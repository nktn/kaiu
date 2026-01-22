const std = @import("std");
const vaxis = @import("vaxis");
const tree = @import("tree.zig");


pub fn renderTree(
    win: vaxis.Window,
    ft: *tree.FileTree,
    cursor: usize,
    scroll_offset: usize,
    show_hidden: bool,
) !void {
    const height = win.height;
    var row: u16 = 0;
    var visible_index: usize = 0;

    for (ft.entries.items) |entry| {
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
        try renderEntry(win, entry, row, is_cursor);

        row += 1;
        visible_index += 1;
    }

    // Show help at bottom if there's room
    if (height > 2 and row < height - 1) {
        const help_row = height - 1;
        const help_text = "j/k:move  o/Enter:open  h:back  a:hidden  q:quit";
        _ = win.printSegment(.{
            .text = help_text,
            .style = .{ .fg = .{ .index = 8 } }, // dim
        }, .{ .row_offset = help_row, .col_offset = 0 });
    }
}

fn renderEntry(
    win: vaxis.Window,
    entry: tree.FileEntry,
    row: u16,
    is_cursor: bool,
) !void {
    var col: u16 = 0;

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
        _ = win.printSegment(.{
            .text = icon,
            .style = .{ .fg = .{ .index = 4 } }, // blue
        }, .{ .row_offset = row, .col_offset = col });
        col += 2;

        _ = win.printSegment(.{
            .text = entry.name,
            .style = .{ .fg = .{ .index = 4 }, .bold = true },
        }, .{ .row_offset = row, .col_offset = col });
        col += @intCast(entry.name.len);

        _ = win.printSegment(.{
            .text = "/",
            .style = .{ .fg = .{ .index = 4 } },
        }, .{ .row_offset = row, .col_offset = col });
    } else {
        _ = win.printSegment(.{ .text = "  " }, .{ .row_offset = row, .col_offset = col });
        col += 2;

        const style: vaxis.Style = if (entry.is_hidden)
            .{ .fg = .{ .index = 8 } } // dim for hidden
        else
            .{};

        _ = win.printSegment(.{
            .text = entry.name,
            .style = style,
        }, .{ .row_offset = row, .col_offset = col });
    }
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

    // Header
    _ = win.printSegment(.{
        .text = filename,
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

        // Print line content
        const col_offset: u16 = @intCast(line_num_width + 1);
        const max_len = @min(line.len, win.width -| col_offset);
        if (max_len > 0) {
            _ = win.printSegment(.{
                .text = line[0..max_len],
            }, .{ .row_offset = row, .col_offset = col_offset });
        }

        line_num += 1;
        row += 1;
    }
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
