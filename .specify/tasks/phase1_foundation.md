# Phase 1 Tasks: Tree View & Preview

## Task 1.1: Project Setup

- [x] Initialize Zig project with `zig init`
- [x] Add libvaxis as dependency in `build.zig.zon`
- [x] Configure `build.zig` to import vaxis module
- [x] Verify `zig build` works
- [x] Create basic project structure:
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

- [x] Parse command line arguments
- [x] `kaiu` (no args) opens current directory
- [x] `kaiu <path>` opens specified directory
- [x] Expand `~` to home directory
- [x] Show error for invalid/non-existent path

---

## Task 1.3: Directory Reading

- [x] Implement `tree.zig` with FileTree struct
- [x] Read directory entries using `std.fs`
- [x] Sort entries: directories first, then files, alphabetically
- [x] Track expand/collapse state for directories
- [x] Detect hidden files (starting with `.`)
- [x] Handle permission errors gracefully

---

## Task 1.4: Basic TUI

- [x] Initialize libvaxis terminal
- [x] Implement main event loop
- [x] Handle terminal resize events
- [x] Handle `q` to quit cleanly
- [x] Clean up terminal on exit

---

## Task 1.5: Tree Rendering

- [x] Render file tree with proper indentation
- [x] Show directories with `/` suffix or folder icon
- [x] Show visual cursor indicator (`>`)
- [x] Handle scrolling when cursor moves off screen

---

## Task 1.6: Cursor Navigation

- [x] Implement `j` to move cursor down
- [x] Implement `k` to move cursor up
- [x] Implement `↓` arrow key (same as `j`)
- [x] Implement `↑` arrow key (same as `k`)
- [x] Handle edge cases (top/bottom of list)
- [x] Update scroll offset to follow cursor

---

## Task 1.7: Directory Expand/Collapse

- [x] Implement `l` to expand directory
- [x] Implement `l` on file to open preview
- [x] Implement `h` to collapse expanded directory
- [x] Implement `h` on file to move cursor to parent directory
- [x] Implement `H` to collapse all directories
- [x] Implement `L` to expand all directories
- [x] Implement `→` arrow key (same as `l`)
- [x] Implement `←` arrow key (same as `h`)

---

## Task 1.8: Hidden Files Toggle

- [x] Hide dotfiles by default
- [x] Implement `.` to toggle hidden files visibility
- [x] Preserve cursor position after toggle (clamp if needed)

---

## Task 1.9: File Preview

- [x] Implement `o` to open full-screen preview
- [x] Implement `o` in preview mode to close (toggle)
- [x] Read and display file content with line numbers
- [x] Handle binary files (show "[Binary file - X bytes]")
- [x] Handle large files (show "[File too large]")
- [x] Handle access denied (show "[Access Denied]")

---

## Task 1.10: Preview Navigation

- [x] Implement `j` in preview mode to scroll down
- [x] Implement `k` in preview mode to scroll up
- [x] Show filename in preview header
- [x] Show help hint in preview footer

---

## Task 1.11: Status Bar

- [x] Show current directory path in header
- [x] Show keybinding hints in footer
- [x] Different hints for tree view vs preview mode

---

## Definition of Done

Each task is complete when:
1. Feature works as described in spec
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on terminal
