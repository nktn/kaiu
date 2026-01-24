---
name: zig-file-operations-error-handling
description: Error handling pattern for file operations in Zig TUI applications
---

# Zig File Operations Error Handling

**Extracted:** 2026-01-24
**Context:** TUI applications with file operations (paste, delete, rename, create)

## Problem

File operations can fail for various reasons (permission denied, file not found, path conflicts). In a TUI application, the application must:

1. Handle errors gracefully without crashing
2. Provide user-friendly feedback
3. Continue running after errors
4. Handle filename conflicts intelligently

## Solution

### Pattern 1: Status Message for Error Feedback

Use a `status_message` field in app state to communicate errors to the user.

```zig
pub const App = struct {
    status_message: ?[]const u8,
    // ... other fields
};

fn createFile(self: *Self) !void {
    const file = std.fs.cwd().createFile(new_path, .{ .exclusive = true }) catch |err| {
        self.status_message = switch (err) {
            error.PathAlreadyExists => "File already exists",
            error.AccessDenied => "Permission denied",
            else => "Failed to create file",
        };
        self.mode = .tree_view;
        return;
    };
    file.close();
    self.status_message = "File created";
}
```

### Pattern 2: Filename Conflict Resolution

When pasting files, handle conflicts by appending numeric suffixes.

```zig
fn pasteFiles(self: *Self) !void {
    for (self.clipboard_files.items) |src_path| {
        const filename = std.fs.path.basename(src_path);
        var final_dest = try std.fs.path.join(self.allocator, &.{ dest_dir, filename });
        var owned_final = false;
        var suffix: usize = 1;

        // Retry with suffix if file exists
        while (std.fs.cwd().access(final_dest, .{})) |_| {
            if (owned_final) self.allocator.free(final_dest);

            const ext = std.fs.path.extension(filename);
            const stem = filename[0 .. filename.len - ext.len];
            const new_name = try std.fmt.allocPrint(
                self.allocator,
                "{s}_{d}{s}",
                .{ stem, suffix, ext }
            );
            defer self.allocator.free(new_name);

            final_dest = try std.fs.path.join(self.allocator, &.{ dest_dir, new_name });
            owned_final = true;
            suffix += 1;
            if (suffix > 100) break; // Safety limit
        } else |_| {
            // File doesn't exist, proceed
        }

        // Perform copy/move to final_dest
        // ...

        if (owned_final) self.allocator.free(final_dest);
    }
}
```

### Pattern 3: Confirmation for Destructive Actions

Use a separate AppMode for confirmation dialogs.

```zig
pub const AppMode = enum {
    tree_view,
    confirm_delete,
    // ... other modes
};

fn enterConfirmDeleteMode(self: *Self) void {
    self.mode = .confirm_delete;
}

fn handleConfirmDeleteKey(self: *Self, key_char: u21) !void {
    switch (key_char) {
        'y' => {
            try self.performDelete();
            self.mode = .tree_view;
        },
        'n', vaxis.Key.escape => {
            self.mode = .tree_view;
        },
        else => {},
    }
}
```

### Pattern 4: Partial Success Handling

Continue processing even if some operations fail.

```zig
fn performDelete(self: *Self) !void {
    var deleted_count: usize = 0;

    for (paths_to_delete.items) |path| {
        self.deletePathRecursive(path) catch {
            // Continue deleting others even if one fails
            continue;
        };
        deleted_count += 1;
    }

    if (deleted_count > 0) {
        self.status_message = "Deleted";
        try self.reloadTree();
    } else {
        self.status_message = "Delete failed";
    }
}
```

### Pattern 5: Recursive Directory Deletion

Safely delete directories recursively.

```zig
fn deletePathRecursive(self: *Self, path: []const u8) !void {
    const stat = std.fs.cwd().statFile(path) catch |err| return err;

    if (stat.kind == .directory) {
        // Delete directory and contents
        try std.fs.cwd().deleteTree(path);
    } else {
        // Delete regular file
        try std.fs.cwd().deleteFile(path);
    }
}
```

## When to Use

- TUI file managers/explorers
- Applications with user-initiated file operations
- When user-friendly error messages are critical
- When destructive operations need confirmation

## Benefits

1. **Robust**: Handles errors without crashing
2. **User-friendly**: Clear error messages in status bar
3. **Safe**: Confirmation for destructive actions
4. **Smart**: Automatic conflict resolution
5. **Resilient**: Partial success handling

## Related Patterns

- State machine for mode management
- Arena allocator for temporary string operations
- StringHashMap for tracking marked files
