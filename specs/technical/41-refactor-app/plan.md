# Technical Plan: app.zig を複数モジュールに分割

- **Issue**: #41
- **Branch**: `technical/41-refactor-app`
- **Created**: 2026-01-25

## 概要

`src/app.zig` (2253行) を複数のモジュールに分割し、可読性・保守性を向上させる。

## 現状分析

```
app.zig セクション構成:
├── AppMode, Event, PendingKey (1-55)
├── App struct 定義 (56-200)
├── init/deinit/run (200-250)
├── Event handlers (250-520)
│   ├── handleKey, handleMouse
│   ├── handleTreeViewKey, handlePreviewKey
│   ├── handleSearchKey, handleRenameKey
│   ├── handleNewFileKey, handleNewDirKey
│   ├── handleConfirmDeleteKey, handleHelpKey
├── Navigation helpers (520-780)
│   ├── moveCursor, updateScrollOffset
│   ├── expandOrEnter, handleBack
│   ├── Expand/Collapse helpers
│   ├── Jump commands (gg/G)
│   ├── Expand/Collapse all
├── Search mode (780-850)
├── Reload tree (850-960)
├── File operations (960-1530)
│   ├── File marking
│   ├── Yank/Cut/Paste
│   ├── Clipboard (OSC 52)
│   ├── Rename mode
│   ├── New file mode
│   ├── New dir mode
│   ├── Confirm delete mode
├── Help mode (1530-1540)
├── Render (1540-1850)
├── Helper functions (1850-1950)
└── Tests (1950-2253)
```

## 分割方針

**段階的アプローチ**: 一度に全部分割せず、効果の高い部分から順次分割。

### Phase 1: file_ops.zig (今回)

ファイル操作関連を抽出（最も独立性が高い）:

| 抽出対象 | 行数 |
|---------|------|
| File marking | ~50 |
| Yank/Cut/Paste | ~150 |
| Rename helpers | ~90 |
| New file/dir helpers | ~145 |
| Delete helpers | ~110 |
| **合計** | **~545行** |

### Phase 2: 評価 (将来)

Phase 1 完了後に再評価:
- app.zig が 1700行程度に削減
- さらに分割が必要か判断
- search.zig, preview.zig 等を検討

## 設計判断

### 判断1: モジュール間の依存関係

**問題**: file_ops の関数は App の状態にアクセスが必要

**解決策**: App への参照を渡す

```zig
// file_ops.zig
pub fn performPaste(app: *App) !void {
    // app.file_clipboard, app.marked_files 等にアクセス
}
```

### 判断2: 循環参照の回避

**問題**: file_ops.zig が app.zig を import し、app.zig が file_ops.zig を import

**解決策**:
- file_ops.zig は App 型を引数で受け取る（import せず）
- app.zig から file_ops の関数を呼び出す

```zig
// app.zig
const file_ops = @import("file_ops.zig");

// handleTreeViewKey 内
'p' => try file_ops.performPaste(self),
```

### 判断3: テストの配置

**決定**: テストは各モジュールに配置

**理由**:
- 関連するテストを近くに保持
- モジュール単体でテスト可能

## 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/app.zig` | file_ops 関連コードを削除、import 追加 |
| `src/file_ops.zig` | 新規作成 |
| `build.zig` | 変更不要（同一パッケージ内） |

## リスク

1. **循環参照**: 設計で回避済み
2. **テスト失敗**: 段階的に移行し、各ステップでテスト確認
3. **機能退行**: 既存テストが全て通ることを確認

## 参照

- Issue: #41
- 関連: Issue #43 (gn 削除) - 完了済み
