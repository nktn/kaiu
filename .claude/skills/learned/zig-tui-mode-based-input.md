---
name: zig-tui-mode-based-input
description: Reusable input buffer pattern for multiple TUI modes
---

# Zig TUI Mode-Based Input Pattern

**Extracted:** 2026-01-24
**Context:** TUI applications with multiple input modes (search, path input, rename, create file/directory)

## Problem

A TUI application needs multiple input modes that share similar behavior:
- Text input with backspace support
- Enter to confirm
- Esc to cancel
- Different prompts and actions per mode

Creating separate input buffers and handlers for each mode leads to code duplication.

## Solution

### Shared Input Buffer with Mode-Specific Handlers

Use a single `input_buffer: std.ArrayList(u8)` and switch behavior based on `AppMode`.

```zig
pub const AppMode = enum {
    tree_view,
    search,
    path_input,
    rename,
    new_file,
    new_dir,
    // ... other modes
};

pub const App = struct {
    mode: AppMode,
    input_buffer: std.ArrayList(u8),
    // ... other fields

    fn handleKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
        switch (self.mode) {
            .tree_view => try self.handleTreeViewKey(key_char),
            .search => try self.handleSearchKey(key, key_char),
            .path_input => try self.handlePathInputKey(key, key_char),
            .rename => try self.handleRenameKey(key, key_char),
            .new_file => try self.handleNewFileKey(key, key_char),
            .new_dir => try self.handleNewDirKey(key, key_char),
            // ... other modes
        }
    }
};
```

### Generic Input Handler Template

All input modes share similar key handling structure:

```zig
fn handleInputModeKey(self: *Self, key: vaxis.Key, key_char: u21) !void {
    switch (key_char) {
        vaxis.Key.escape => {
            // Cancel and return to normal mode
            self.input_buffer.clearRetainingCapacity();
            self.mode = .tree_view;
        },
        vaxis.Key.enter => {
            // Mode-specific action
            try self.performModeSpecificAction();
        },
        vaxis.Key.backspace => {
            // Remove last character
            if (self.input_buffer.items.len > 0) {
                _ = self.input_buffer.pop();
            }
        },
        else => {
            // Add printable character
            if (key_char >= 0x20 and key_char < 0x7F) {
                try self.input_buffer.append(self.allocator, @intCast(key_char));
            }
        },
    }
    _ = key;
}
```

### Mode Entry with Initial Value

For rename mode, populate `input_buffer` with current filename:

```zig
fn enterRenameMode(self: *Self) !void {
    if (self.file_tree == null) return;
    const ft = self.file_tree.?;

    const actual_index = ft.visibleToActualIndex(self.cursor, self.show_hidden) orelse return;
    const entry = &ft.entries.items[actual_index];

    // Clear previous input
    self.input_buffer.clearRetainingCapacity();

    // Populate with current name
    try self.input_buffer.appendSlice(self.allocator, entry.name);

    // Store target path for rename
    self.rename_target_path = entry.path;
    self.mode = .rename;
}
```

For new file/directory modes, start with empty buffer:

```zig
fn enterNewFileMode(self: *Self) void {
    self.input_buffer.clearRetainingCapacity();
    self.mode = .new_file;
}
```

### Rendering Mode-Specific Prompts

Render different prompts based on mode:

```zig
fn renderStatusBar(win: vaxis.Window, app: *const App) void {
    const prompt = switch (app.mode) {
        .search => "Search: ",
        .path_input => "Go to: ",
        .rename => "Rename: ",
        .new_file => "New file: ",
        .new_dir => "New directory: ",
        else => "",
    };

    if (prompt.len > 0) {
        try win.print(prompt ++ "{s}", .{app.input_buffer.items});
    }
}
```

## When to Use

- TUI applications with multiple text input scenarios
- When input modes share common key handling (Enter, Esc, Backspace)
- When you want to avoid duplicating input logic
- Search, path navigation, rename, create operations

## Benefits

1. **DRY**: Single input buffer, single set of key handling code
2. **Consistent UX**: All input modes behave similarly
3. **Easy to extend**: Add new input mode by adding enum value and handler
4. **Memory efficient**: No duplicate allocations
5. **Maintainable**: Changes to input behavior apply to all modes

## Implementation Notes

### Memory Management

The input buffer is owned by App and persists across mode changes:

```zig
pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !*App {
    // ...
    .input_buffer = std.ArrayList(u8).init(allocator),
}

pub fn deinit(self: *Self) void {
    self.input_buffer.deinit();
    // ... other cleanup
}
```

### Clearing Between Modes

Use `clearRetainingCapacity()` to reuse allocated memory:

```zig
self.input_buffer.clearRetainingCapacity(); // Keeps capacity, clears items
```

### Mode-Specific State

For modes that need additional state (e.g., rename needs target path):

```zig
pub const App = struct {
    rename_target_path: ?[]const u8,
    // ...
};
```

## Related Patterns

- State machine for mode management
- Status message pattern for feedback
- Arena allocator for temporary rendering strings
