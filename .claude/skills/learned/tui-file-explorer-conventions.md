---
name: tui-file-explorer-conventions
description: Design conventions for TUI file explorers based on ranger, lf, nnn
---

# TUI File Explorer Design Conventions

**Extracted:** 2026-01-24
**Context:** When designing a TUI file explorer for Unix-like systems

## Problem
Deciding which features are standard for TUI file explorers vs. overengineering

## Solution

### Standard Features (Include)
- **Navigation**: Vim-style hjkl, gg/G jumps
- **File Operations**: mark, yank (copy), cut, paste, delete, rename, create
- **Confirmation Dialogs**: Delete confirmation (y/n)
- **Visual Feedback**: Status messages, error notifications
- **Search**: Incremental search with highlighting
- **Preview**: File content preview
- **Hidden Files**: Toggle visibility

### Non-standard Features (Skip)
- **Undo/Redo**: Typical TUI explorers (ranger, lf, nnn) do NOT have undo
  - Rationale: Delete confirmation is sufficient for safety
  - Complexity: Tracking file system state across operations is complex
  - Edge cases: Symlinks, directory moves, external changes
- **Trash/Recycle Bin**: Not common in TUI explorers
- **File History**: Not common

## When to Use

When designing a new TUI file explorer, follow these conventions unless there's a strong reason to deviate:

1. **Check existing tools**: Look at ranger, lf, nnn for feature expectations
2. **Prefer simplicity**: Users expect lightweight, fast tools
3. **Confirmation over undo**: Delete confirmation is standard practice
4. **Unix philosophy**: Do one thing well, don't duplicate OS features

## Examples

**Good**: Delete with confirmation dialog
```zig
TreeView --> ConfirmDelete: D key
ConfirmDelete --> TreeView: y (delete) / n (cancel)
```

**Bad**: Complex undo stack
```zig
// NOT standard for TUI explorers
pub const UndoState = struct {
    operations: ArrayList(UndoEntry),
    current_index: usize,
};
```

## Reference
- ranger: https://github.com/ranger/ranger (no undo)
- lf: https://github.com/gokcehan/lf (no undo)
- nnn: https://github.com/jarun/nnn (no undo)
