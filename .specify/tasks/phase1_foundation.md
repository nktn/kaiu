# Phase 1 Tasks: Foundation

## Task 1.1: Project Setup

- [x] Initialize Zig project with `zig init`
- [x] Add libvaxis as dependency in `build.zig.zon`:
```zig
  .dependencies = .{
      .vaxis = .{
          .url = "https://github.com/neurocyte/libvaxis/archive/refs/heads/master.tar.gz",
          // hash は最初のビルド時にエラーで表示される
      },
  },
```
- [x] `build.zig` で vaxis モジュールを追加:
```zig
  const vaxis = b.dependency("vaxis", .{});
  exe.root_module.addImport("vaxis", vaxis.module("vaxis"));
```
- [x] `zig build` を実行して依存関係を取得・ビルド確認
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
- [x] Verify `zig build` works

---

## Task 1.2: Directory Reading

- [x] Implement `tree.zig` with FileTree struct
- [x] Read directory entries using `std.fs`
- [x] Sort entries: directories first, then files, alphabetically
- [x] Handle permission errors gracefully
- [x] Support expand/collapse state for directories

---

## Task 1.3: Basic TUI

- [x] Initialize libvaxis terminal
- [x] Implement main event loop
- [x] Render file tree with indentation
- [x] Show cursor position
- [x] Handle `q` to quit cleanly

---

## Task 1.4: Navigation

- [x] Implement `j` / `k` movement
- [x] Implement `Enter` to expand/collapse directories
- [x] Add visual cursor indicator (`>` or highlight)
- [x] Handle edge cases (empty directory, single file)

---

## Task 1.5: Hidden Files

- [x] Filter out dotfiles by default
- [x] Implement `a` to toggle visibility
- [x] Show indicator when hidden files exist but are hidden

---

## Task 1.6: Split Layout

- [x] Implement two-pane layout (tree | preview)
- [x] Calculate pane widths dynamically
- [x] Handle terminal resize events

---

## Task 1.7: Text Preview

- [x] Read file content on selection
- [x] Display with line numbers
- [x] Truncate large files (>1000 lines)
- [x] Show "[truncated]" indicator

---

## Task 1.8: Preview Navigation

- [x] `l` or `Enter` on file opens preview
- [x] `h` closes preview, returns focus to tree
- [x] Preview scrolling with `j`/`k` when focused
- [x] Show filename in preview header

---

## Task 1.9: File Type Handling

- [x] Detect binary files (null bytes check)
- [x] Show "[Binary file - X bytes]" for binary

---

## Definition of Done

Each task is complete when:
1. Feature works as described
2. No crashes on edge cases
3. Code compiles without warnings
4. Tested manually on Ghostty
```

---

## 4. README.md（変更なし）

先ほどの内容そのままで OK。

---

## Claude Code での構造
```
kaiu/
├── README.md
├── .specify/
│   ├── memory/
│   │   └── constitution.md
│   ├── specs/
│   │   └── phase1_tree_view.md
│   └── tasks/
│       └── phase1_foundation.md