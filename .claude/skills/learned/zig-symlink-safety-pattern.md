---
name: zig-symlink-safety-pattern
description: Safe handling of symbolic links in recursive file operations
---

# Zig Symlink Safety Pattern

**Extracted:** 2026-01-25
**Context:** Recursive directory operations (copy, delete) that may encounter symbolic links

## Problem

When performing recursive file operations, symbolic links introduce security and correctness risks:

1. **Security**: Using `statFile()` before deletion follows symlinks, leading to incorrect decision paths
2. **Infinite loops**: Symlink cycles (A → B → A) cause infinite recursion
3. **Unexpected behavior**: Following symlinks during copy might duplicate large directory trees
4. **User expectation**: Users expect symlinks to be preserved, not followed

## Solution

### Pattern 1: Detect Symlinks BEFORE Following Them

Use `readLink()` to detect symlinks **before** calling `statFile()`, which follows symlinks.

```zig
/// Delete a file or directory recursively with symlink safety
pub fn deletePathRecursive(path: []const u8) !void {
    // Security: Check if path is a symlink FIRST before following it
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;

    if (std.fs.cwd().readLink(path, &link_buf)) |_| {
        // It's a symlink - delete only the symlink itself, not the target
        try std.fs.cwd().deleteFile(path);
        return;
    } else |_| {
        // Not a symlink, continue with normal deletion
    }

    // Now safe to check what it actually is
    const stat = try std.fs.cwd().statFile(path);
    if (stat.kind == .directory) {
        try std.fs.cwd().deleteTree(path);
    } else {
        try std.fs.cwd().deleteFile(path);
    }
}
```

**Why this order matters**:
```zig
// ❌ WRONG ORDER - statFile follows symlink before detecting it
const stat = try std.fs.cwd().statFile(path); // statFile() FOLLOWS symlinks
if (stat.kind == .directory) {
    // deleteTree does NOT follow symlinks, but wrong branch was taken
    try std.fs.cwd().deleteTree(path);
}

// ✅ CORRECT ORDER - detects symlink first
if (std.fs.cwd().readLink(path, &buf)) |_| {
    try std.fs.cwd().deleteFile(path); // Deletes only the symlink
    return;
} else |_| {}
const stat = try std.fs.cwd().statFile(path);
```

### Pattern 2: Preserve Symlinks During Copy

When copying directories, preserve symlinks as symlinks (don't follow them).

```zig
pub fn copyDirRecursive(src_path: []const u8, dest_path: []const u8) !void {
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check if source is a symlink - if so, copy the symlink itself
    if (std.fs.cwd().readLink(src_path, &link_buf)) |link_target| {
        // Copy symlink: create a new symlink at dest_path pointing to same target
        try std.posix.symlink(link_target, dest_path);
        return;
    } else |_| {}

    // Not a symlink - create directory and copy contents
    try std.fs.cwd().makeDir(dest_path);

    var src_dir = try std.fs.cwd().openDir(src_path, .{ .iterate = true });
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_child = try std.fs.path.join(allocator, &.{ src_path, entry.name });
        const dest_child = try std.fs.path.join(allocator, &.{ dest_path, entry.name });

        // Check each child for symlinks
        if (std.fs.cwd().readLink(src_child, &link_buf)) |link_target| {
            try std.posix.symlink(link_target, dest_child);
            continue;
        } else |_| {}

        if (entry.kind == .directory) {
            try copyDirRecursive(src_child, dest_child);
        } else {
            try std.fs.cwd().copyFile(src_child, std.fs.cwd(), dest_child, .{});
        }
    }
}
```

### Pattern 3: Use readLink() for Detection, Not stat()

```zig
// ❌ WRONG - stat() follows symlinks
const stat = try std.fs.cwd().statFile(path);
if (stat.kind == .sym_link) { // This will NEVER be true with statFile()!
    // ...
}

// ✅ CORRECT - readLink() detects symlinks without following
var buf: [std.fs.max_path_bytes]u8 = undefined;
if (std.fs.cwd().readLink(path, &buf)) |target| {
    // It's a symlink, target contains the link destination
    std.debug.print("Symlink: {s} -> {s}\n", .{ path, target });
} else |_| {
    // Not a symlink
}
```

### API Reference: Zig std.fs Symlink Behavior

| Function | Follows Symlinks? | Use Case |
|----------|-------------------|----------|
| `statFile()` | ✅ YES | Get info about symlink target |
| `readLink()` | ❌ NO | Detect if path is a symlink |
| `deleteFile()` | ❌ NO | Delete symlink itself |
| `deleteTree()` | ❌ NO | Delete directory contents (does not follow symlinks) |
| `copyFile()` | ✅ YES | Copies symlink target's content |
| `openFile()` | ✅ YES | Opens symlink target |

## When to Use

**Use this pattern when**:
- Implementing recursive directory operations (copy, move, delete)
- Building file managers or backup tools
- Traversing directory trees where symlinks may exist

**Critical for**:
- Security-sensitive applications (prevent symlink attacks)
- Data integrity (avoid unintended deletions)
- User expectations (preserve symlinks as symlinks)

## Security Implications

### Symlink Attack Example

Consider this directory structure:
```
/tmp/my_app/
  data/
  temp/ -> /etc/  (symlink to system directory)
```

**Without symlink safety**:
```zig
// ❌ PROBLEMATIC - statFile follows symlink, leading to wrong branch
const stat = try std.fs.cwd().statFile("/tmp/my_app/temp"); // stat.kind = .directory (from /etc)
if (stat.kind == .directory) {
    // deleteTree does NOT follow symlinks - it just deletes the symlink itself
    // But the code took wrong branch because statFile reported it as a directory
    try std.fs.cwd().deleteTree("/tmp/my_app/temp");
}
// Note: deleteTree() does NOT follow symlinks, so /etc is safe here.
// The issue is incorrect decision-making based on statFile() result.
```

**With symlink safety**:
```zig
// ✅ SAFE - detects symlink, deletes only the link
if (std.fs.cwd().readLink("/tmp/my_app/temp", &buf)) |_| {
    try std.fs.cwd().deleteFile("/tmp/my_app/temp"); // Deletes only symlink
    return; // /etc is untouched
}
```

## Testing Strategy

```zig
test "deletePathRecursive deletes symlink, not target" {
    // Setup: Create a target directory and a symlink to it
    try tmp_dir.dir.makeDir("target_dir");
    var target = try tmp_dir.dir.openDir("target_dir", .{});
    var marker = try target.createFile("important.txt", .{});
    marker.close();
    target.close();

    try std.posix.symlinkat("target_dir", tmp_dir.dir.fd, "link_to_target");

    // Delete the symlink
    try deletePathRecursive("link_to_target");

    // Verify: symlink is gone, but target still exists
    _ = tmp_dir.dir.statFile("link_to_target") catch |err| {
        try std.testing.expectEqual(error.FileNotFound, err); // Symlink deleted
    };

    // Target directory and its contents should still exist
    var target_check = try tmp_dir.dir.openDir("target_dir", .{});
    _ = try target_check.statFile("important.txt"); // Still there!
    target_check.close();
}
```

## Common Pitfalls

### ❌ Pitfall 1: Using stat().kind == .sym_link

```zig
// This NEVER works with statFile() because it follows symlinks
const stat = try std.fs.cwd().statFile(path);
if (stat.kind == .sym_link) { // Never true!
    // ...
}
```

**Why**: `statFile()` follows the symlink and returns the target's kind.

### ❌ Pitfall 2: Ignoring Symlink Check Errors

```zig
// BAD - swallows errors silently
if (std.fs.cwd().readLink(path, &buf)) |_| {
    // Handle symlink
} else |_| {
    // Assumes it's not a symlink, but what if readLink failed for another reason?
}
```

**Better**: Only expect specific errors.

```zig
if (std.fs.cwd().readLink(path, &buf)) |link_target| {
    // It's a symlink
} else |err| switch (err) {
    error.NotLink => {}, // Expected: not a symlink
    else => return err, // Unexpected error
}
```

### ❌ Pitfall 3: Forgetting to Check During Iteration

```zig
var iter = src_dir.iterate();
while (try iter.next()) |entry| {
    // ❌ Assumes entry.kind is reliable for symlinks
    if (entry.kind == .directory) {
        try copyDirRecursive(src_child, dest_child); // Might follow symlink!
    }
}
```

**Fix**: Always readLink() before recursing.

## Related Patterns

- Security-first file operations
- Error propagation in file operations
- Recursive traversal with guards

## References

- Zig std.fs documentation
- `.claude/rules/security.md` - File System Security
- kaiu `file_ops.zig` implementation
