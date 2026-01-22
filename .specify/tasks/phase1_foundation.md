# Phase 1 Tasks: Foundation

## Task 1.1: Project Setup

- [ ] Initialize Zig project with `zig init`
- [ ] Add libvaxis as dependency in `build.zig.zon`:
```zig
  .dependencies = .{
      .vaxis = .{
          .url = "https://github.com/neurocyte/libvaxis/archive/refs/heads/master.tar.gz",
          // hash は最初のビルド時にエラーで表示される
      },
  },
```
- [ ] `build.zig` で vaxis モジュールを追加:
```zig
  const vaxis = b.dependency("vaxis", .{});
  exe.root_module.addImport("vaxis", vaxis.module("vaxis"));
```
- [ ] `zig build` を実行して依存関係を取得・ビルド確認
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
- [ ] Verify `zig build` works

---

## Task 1.2: Directory Reading

- [ ] Implement `tree.zig` with FileTree struct
- [ ] Read directory entries using `std.fs`
- [ ] Sort entries: directories first, then files, alphabetically
- [ ] Handle permission errors gracefully
- [ ] Support expand/collapse state for directories

---

## Task 1.3: Basic TUI

- [ ] Initialize libvaxis terminal
- [ ] Implement main event loop
- [ ] Render file tree with indentation
- [ ] Show cursor position
- [ ] Handle `q` to quit cleanly

---

## Task 1.4: Navigation

- [ ] Implement `j` / `k` movement
- [ ] Implement `Enter` to expand/collapse directories
- [ ] Add visual cursor indicator (`>` or highlight)
- [ ] Handle edge cases (empty directory, single file)

---

## Task 1.5: Hidden Files

- [ ] Filter out dotfiles by default
- [ ] Implement `a` to toggle visibility
- [ ] Show indicator when hidden files exist but are hidden

---

## Task 1.6: Split Layout

- [ ] Implement two-pane layout (tree | preview)
- [ ] Calculate pane widths dynamically
- [ ] Handle terminal resize events

---

## Task 1.7: Text Preview

- [ ] Read file content on selection
- [ ] Display with line numbers
- [ ] Truncate large files (>1000 lines)
- [ ] Show "[truncated]" indicator

---

## Task 1.8: Preview Navigation

- [ ] `l` or `Enter` on file opens preview
- [ ] `h` closes preview, returns focus to tree
- [ ] Preview scrolling with `j`/`k` when focused
- [ ] Show filename in preview header

---

## Task 1.9: File Type Handling

- [ ] Detect binary files (null bytes check)
- [ ] Show "[Binary file - X bytes]" for binary

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