# Phase 2 Tasks: File Operations & Utilities

## Task 2.1: File Marking System

- [ ] Add `marked` field to FileEntry or separate marked set
- [ ] Implement `Space` to toggle mark on current file
- [ ] Show visual indicator (`*`) for marked files
- [ ] Track marked file count
- [ ] Show marked count in status bar

---

## Task 2.2: Yank/Cut Operations

- [ ] Create clipboard state (files list + operation type)
- [ ] Implement `y` to yank marked files (or current if none marked)
- [ ] Implement `d` to cut marked files (or current if none marked)
- [ ] Show feedback message "Yanked N files" / "Cut N files"
- [ ] Clear marks after yank/cut

---

## Task 2.3: Paste Operation

- [ ] Implement `p` to paste files to current directory
- [ ] Copy files for yank operation
- [ ] Move files for cut operation (copy + delete source)
- [ ] Handle filename conflicts (append number)
- [ ] Show progress/feedback for large operations
- [ ] Refresh tree after paste

---

## Task 2.4: Delete with Confirmation

- [ ] Implement `D` to trigger delete
- [ ] Show confirmation dialog with file list
- [ ] Implement `y` to confirm deletion
- [ ] Implement `n` / `Esc` to cancel
- [ ] Delete files/directories recursively
- [ ] Handle permission errors gracefully
- [ ] Refresh tree after delete

---

## Task 2.5: Rename

- [ ] Implement `r` to enter rename mode
- [ ] Show inline input with current filename
- [ ] Handle text input (printable chars, backspace)
- [ ] Implement `Enter` to confirm rename
- [ ] Implement `Esc` to cancel
- [ ] Handle rename errors (exists, invalid name)
- [ ] Refresh tree after rename

---

## Task 2.6: Create File/Directory

- [ ] Implement `a` to enter new file mode
- [ ] Implement `A` to enter new directory mode
- [ ] Show input at bottom "New file: " / "New dir: "
- [ ] Create file/directory on `Enter`
- [ ] Handle errors (exists, invalid name, permission)
- [ ] Refresh tree and select new item

---

## Task 2.7: Clipboard (Path Copy)

- [ ] Implement `c` to copy full path to clipboard
- [ ] Implement `C` to copy filename to clipboard
- [ ] Use OSC 52 escape sequence for clipboard
- [ ] Show feedback "Copied: <path>"
- [ ] Handle clipboard not available

---

## Task 2.8: Search Mode

- [ ] Implement `/` to enter search mode
- [ ] Show search input at bottom
- [ ] Capture keystrokes in search mode
- [ ] Highlight matching text with inverted colors (reverse video)
- [ ] Case-insensitive matching
- [ ] Show match count "[N matches]"

---

## Task 2.9: Search Navigation

- [ ] Implement `Enter` to confirm search and jump to first match
- [ ] Implement `n` to jump to next match
- [ ] Implement `N` to jump to previous match
- [ ] Wrap around at list ends
- [ ] Implement `Esc` to cancel search
- [ ] Maintain match highlighting after search confirm

---

## Task 2.10: Jump Navigation

- [ ] Implement `gg` (two-key sequence) to jump to first item
- [ ] Implement `G` to jump to last item
- [ ] Handle pending key state for `g` prefix
- [ ] Show pending key indicator "g-" in status bar

---

## Task 2.11: Help Overlay

- [ ] Implement `?` to show help overlay
- [ ] Create help overlay UI with all keybindings
- [ ] Organize keybindings by category
- [ ] Any key dismisses overlay
- [ ] Overlay covers main UI but preserves state

---

## Task 2.12: Input Mode Infrastructure

- [ ] Create reusable text input component
- [ ] Handle printable character input
- [ ] Handle backspace/delete
- [ ] Handle cursor movement (optional)
- [ ] Share between rename, new file, new dir, search

---

## Task 2.13: Status Bar Enhancements

- [ ] Show marked file count when > 0
- [ ] Show clipboard state (N files yanked/cut)
- [ ] Show search match info "[N/M]"
- [ ] Show pending key indicator
- [ ] Context-sensitive keybinding hints

---

## Definition of Done

Each task is complete when:
1. Feature works as described in spec
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on terminal
5. Phase 1 features still work correctly
