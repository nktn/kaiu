# Phase 2 Tasks: Vim Motions & Navigation

## Task 2.1: Multi-Key Command Buffer

- [ ] Create command buffer to handle multi-key sequences (`gg`, `gn`)
- [ ] Implement timeout mechanism (500ms)
- [ ] Show pending key in status bar (e.g., `g-`)
- [ ] Cancel pending state on timeout or different key
- [ ] Support extensible command registration for future commands

---

## Task 2.2: Jump Commands

- [ ] Implement `gg` (jump to first item)
- [ ] Implement `G` (jump to last item)
- [ ] Update cursor position and scroll view
- [ ] Handle empty directory edge case

---

## Task 2.3: Expand/Collapse All

- [ ] Implement `H` (collapse all directories)
- [ ] Implement `L` (expand all directories)
- [ ] Implement `Tab` (toggle current directory)
- [ ] For `L`, handle deep trees with loading indicator
- [ ] Maintain cursor position after operation

---

## Task 2.4: Path Navigation (gn)

- [ ] Implement `gn` to enter path input mode
- [ ] Show input bar at bottom "Go to: "
- [ ] Handle text input (printable characters, backspace)
- [ ] Expand `~` to home directory
- [ ] Resolve `..` and `.` in path
- [ ] `Enter` validates and navigates to path
- [ ] `Esc` cancels and returns to normal mode
- [ ] Show error for invalid/non-existent path
- [ ] If path is file, navigate to parent and select file

---

## Task 2.5: Search Mode UI

- [ ] Implement `/` to enter search mode
- [ ] Show search input bar at bottom
- [ ] Capture keystrokes in search mode
- [ ] Display current search query with cursor
- [ ] Show match count `[N matches]`
- [ ] `Esc` exits search mode and clears query
- [ ] `Enter` confirms search and returns to normal mode

---

## Task 2.6: Search Filtering

- [ ] Filter visible tree items by search query
- [ ] Case-insensitive matching
- [ ] Match against filename (not full path)
- [ ] Update results incrementally as user types
- [ ] Auto-jump cursor to first match

---

## Task 2.7: Search Match Highlighting

- [ ] Mark matching items with visual indicator `[*]`
- [ ] Optionally highlight matched substring in filename
- [ ] Maintain highlight after exiting search mode

---

## Task 2.8: Search Navigation

- [ ] Implement `n` to jump to next match
- [ ] Implement `N` to jump to previous match
- [ ] Wrap around at list ends
- [ ] No-op if no active search or no matches
- [ ] Update status bar with current match index `[2/5]`

---

## Task 2.9: Toggle Hidden Files

- [ ] Change keybinding from `a` to `.`
- [ ] Toggle visibility of dotfiles
- [ ] Refresh tree view after toggle
- [ ] Show indicator in status bar when hidden files are shown

---

## Task 2.10: Reload Tree

- [ ] Implement `R` to reload tree
- [ ] Re-read directory from filesystem
- [ ] Preserve expanded/collapsed state where possible
- [ ] Preserve cursor position if file still exists
- [ ] Show "Reloaded" feedback message

---

## Task 2.11: Clipboard Operations

- [ ] Implement `c` to copy full path to clipboard
- [ ] Implement `C` to copy filename to clipboard
- [ ] Use system clipboard (OSC 52 or platform-specific)
- [ ] Show feedback "Copied: <path>" in status bar
- [ ] Handle clipboard not available error

---

## Task 2.12: Help Overlay

- [ ] Implement `?` to show help overlay
- [ ] Create help overlay UI with all keybindings
- [ ] Organize keybindings by category
- [ ] Any key press dismisses overlay
- [ ] Overlay covers main UI but doesn't destroy state

---

## Task 2.13: Integration & Polish

- [ ] Update status bar to show current mode (NORMAL / SEARCH / INPUT)
- [ ] Test all edge cases from spec
- [ ] Ensure no regressions in Phase 1 features
- [ ] Update README with new keybindings

---

## Definition of Done

Each task is complete when:
1. Feature works as described in spec
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on Ghostty
5. Phase 1 features still work correctly