# Architecture Decisions

このファイルは実装中に zig-architect が更新する設計書。

## State Machine

### App States

```mermaid
stateDiagram-v2
    [*] --> TreeView: init

    TreeView --> TreeView: j (cursor down)
    TreeView --> TreeView: k (cursor up)
    TreeView --> TreeView: Enter on dir (toggle expand)
    TreeView --> TreeView: h on expanded (collapse)
    TreeView --> TreeView: a (toggle hidden)
    TreeView --> Preview: l/Enter on file
    TreeView --> [*]: q (quit)

    Preview --> Preview: j (scroll down)
    Preview --> Preview: k (scroll up)
    Preview --> TreeView: h (close)
    Preview --> [*]: q (quit)
```

### State Transitions

| From | Event | To | Action |
|------|-------|-----|--------|
| TreeView | `j` | TreeView | cursor_down() |
| TreeView | `k` | TreeView | cursor_up() |
| TreeView | `l`/`Enter` on dir | TreeView | toggle_expand() |
| TreeView | `l`/`Enter` on file | Preview | open_preview() |
| TreeView | `h` on expanded dir | TreeView | collapse() |
| TreeView | `a` | TreeView | toggle_hidden() |
| TreeView | `q` | Quit | cleanup() |
| Preview | `h` | TreeView | close_preview() |
| Preview | `j` | Preview | scroll_down() |
| Preview | `k` | Preview | scroll_up() |
| Preview | `q` | Quit | cleanup() |

### State Enum

```zig
pub const AppMode = enum {
    tree_view,
    preview,
};
```

## Module Structure

```
src/
├── main.zig      # Entry point
├── app.zig       # App state, event loop, state machine
├── tree.zig      # FileTree data structure
└── ui.zig        # libvaxis rendering
```

## Memory Strategy

| Module | Allocator | Rationale |
|--------|-----------|-----------|
| (未定) | | |

## Error Sets

```zig
// 定義され次第追記
```

## Data Structures

### FileTree
- (実装時に詳細追記)

### AppState
- (実装時に詳細追記)

## Design Decisions Log

<!-- zig-architect が判断時に追記 -->

### [YYYY-MM-DD] Decision Title
**Context**: 何が必要だったか
**Decision**: 何を選んだか
**Rationale**: なぜ選んだか
**Alternatives**: 他の選択肢

---

<!-- New decisions above this line -->
