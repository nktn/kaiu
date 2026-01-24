# Phase 2 Tasks: File Operations & Utilities

## Task 2.1: File Marking System

- [x] Add `marked` field to FileEntry or separate marked set
- [x] Implement `Space` to toggle mark on current file
- [x] Show visual indicator (`*`) for marked files
- [x] Track marked file count
- [x] Show marked count in status bar

---

## Task 2.2: Yank/Cut Operations

- [x] Create clipboard state (files list + operation type)
- [x] Implement `y` to yank marked files (or current if none marked)
- [x] Implement `d` to cut marked files (or current if none marked)
- [x] Show feedback message "Yanked N files" / "Cut N files"
- [x] Clear marks after yank/cut

---

## Task 2.3: Paste Operation

- [x] Implement `p` to paste files to current directory
- [x] Copy files for yank operation
- [x] Move files for cut operation (copy + delete source)
- [x] Handle filename conflicts (append number)
- [x] Show progress/feedback for large operations
- [x] Refresh tree after paste

---

## Task 2.4: Delete with Confirmation

- [x] Implement `D` to trigger delete
- [x] Show confirmation dialog with file list
- [x] Implement `y` to confirm deletion
- [x] Implement `n` / `Esc` to cancel
- [x] Delete files/directories recursively
- [x] Handle permission errors gracefully
- [x] Refresh tree after delete

---

## Task 2.5: Rename

- [x] Implement `r` to enter rename mode
- [x] Show inline input with current filename
- [x] Handle text input (printable chars, backspace)
- [x] Implement `Enter` to confirm rename
- [x] Implement `Esc` to cancel
- [x] Handle rename errors (exists, invalid name)
- [x] Refresh tree after rename

---

## Task 2.6: Create File/Directory

- [x] Implement `a` to enter new file mode
- [x] Implement `A` to enter new directory mode
- [x] Show input at bottom "New file: " / "New dir: "
- [x] Create file/directory on `Enter`
- [x] Implement `Esc` to cancel
- [x] Handle errors (exists, invalid name, permission)
- [x] Refresh tree and select new item

---

## Task 2.7: Clipboard (Path Copy)

- [x] Implement `c` to copy full path to clipboard
- [x] Implement `C` to copy filename to clipboard
- [x] Use OSC 52 escape sequence for clipboard
- [x] Show feedback "Copied: <path>"
- [x] Handle clipboard not available

---

## Task 2.8: Search Mode

- [x] Implement `/` to enter search mode
- [x] Show search input at bottom
- [x] Capture keystrokes in search mode
- [x] Highlight matching text with inverted colors (reverse video)
- [x] Case-insensitive matching
- [x] Show match count "[N matches]"

---

## Task 2.9: Search Navigation

- [x] Implement `Enter` to confirm search and jump to first match
- [x] Implement `n` to jump to next match
- [x] Implement `N` to jump to previous match
- [x] Wrap around at list ends
- [x] Implement `Esc` to cancel search
- [x] Maintain match highlighting after search confirm

---

## Task 2.10: Jump Navigation

- [x] Implement `gg` (two-key sequence) to jump to first item
- [x] Implement `G` to jump to last item
- [x] Handle pending key state for `g` prefix
- [x] Show pending key indicator "g-" in status bar

---

## Task 2.11: Help Overlay

- [x] Implement `?` to show help overlay
- [x] Create help overlay UI with all keybindings
- [x] Organize keybindings by category
- [x] Any key dismisses overlay
- [x] Overlay covers main UI but preserves state

---

## Task 2.12: Input Mode Infrastructure

- [x] Create reusable text input component
- [x] Handle printable character input
- [x] Handle backspace/delete
- [x] Handle cursor movement (optional)
- [x] Share between rename, new file, new dir, search

---

## Task 2.13: Status Bar Enhancements

- [x] Show marked file count when > 0
- [x] Show clipboard state (N files yanked/cut)
- [x] Show search match info "[N/M]"
- [x] Show pending key indicator
- [x] Context-sensitive keybinding hints

---

## Task 2.14: Status Bar Path Display (FR-030, FR-031)

- [x] Resolve relative paths (`.`, `..`) to absolute paths
- [x] Replace home directory prefix with `~`
- [x] Update path display in status bar
- [x] Add tests for path expansion

---

## Definition of Done

Each task is complete when:
1. Feature works as described in spec
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on terminal
5. Phase 1 features still work correctly
