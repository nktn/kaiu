# Phase 1 Tasks: Tree View & Preview

## Task 1.1: Project Setup

- [ ] Initialize Zig project with `zig init`
- [ ] Add libvaxis as dependency in `build.zig.zon`
- [ ] Configure `build.zig` to import vaxis module
- [ ] Verify `zig build` works
- [ ] Create basic project structure:
  ```
  kaiu/
  ├── src/
  │   ├── main.zig
  │   ├── app.zig
  │   ├── tree.zig
  │   └── ui.zig
  ├── build.zig
  ├── build.zig.zon
  └── README.md
  ```

---

## Task 1.2: CLI Arguments

- [ ] Parse command line arguments
- [ ] `kaiu` (no args) opens current directory
- [ ] `kaiu <path>` opens specified directory
- [ ] Expand `~` to home directory
- [ ] Show error for invalid/non-existent path

---

## Task 1.3: Directory Reading

- [ ] Implement `tree.zig` with FileTree struct
- [ ] Read directory entries using `std.fs`
- [ ] Sort entries: directories first, then files, alphabetically
- [ ] Track expand/collapse state for directories
- [ ] Detect hidden files (starting with `.`)
- [ ] Handle permission errors gracefully

---

## Task 1.4: Basic TUI

- [ ] Initialize libvaxis terminal
- [ ] Implement main event loop
- [ ] Handle terminal resize events
- [ ] Handle `q` to quit cleanly
- [ ] Clean up terminal on exit

---

## Task 1.5: Tree Rendering

- [ ] Render file tree with proper indentation
- [ ] Show directories with `/` suffix or folder icon
- [ ] Show visual cursor indicator (`>`)
- [ ] Handle scrolling when cursor moves off screen

---

## Task 1.6: Cursor Navigation

- [ ] Implement `j` to move cursor down
- [ ] Implement `k` to move cursor up
- [ ] Implement `↓` arrow key (same as `j`)
- [ ] Implement `↑` arrow key (same as `k`)
- [ ] Handle edge cases (top/bottom of list)
- [ ] Update scroll offset to follow cursor

---

## Task 1.7: Directory Expand/Collapse

- [ ] Implement `l` to expand directory
- [ ] Implement `l` on file to open preview
- [ ] Implement `h` to collapse expanded directory
- [ ] Implement `h` on file to move cursor to parent directory
- [ ] Implement `H` to collapse all directories
- [ ] Implement `L` to expand all directories

---

## Task 1.8: Hidden Files Toggle

- [ ] Hide dotfiles by default
- [ ] Implement `.` to toggle hidden files visibility
- [ ] Preserve cursor position after toggle (clamp if needed)

---

## Task 1.9: File Preview

- [ ] Implement `o` to open full-screen preview
- [ ] Implement `o` in preview mode to close (toggle)
- [ ] Read and display file content with line numbers
- [ ] Handle binary files (show "[Binary file - X bytes]")
- [ ] Handle large files (show "[File too large]")
- [ ] Handle access denied (show "[Access Denied]")

---

## Task 1.10: Preview Navigation

- [ ] Implement `j` in preview mode to scroll down
- [ ] Implement `k` in preview mode to scroll up
- [ ] Show filename in preview header
- [ ] Show help hint in preview footer

---

## Task 1.11: Status Bar

- [ ] Show current directory path in header
- [ ] Show keybinding hints in footer
- [ ] Different hints for tree view vs preview mode

---

## Definition of Done

Each task is complete when:
1. Feature works as described in spec
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on terminal
