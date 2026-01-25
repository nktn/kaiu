# Technical Tasks: app.zig を複数モジュールに分割

**Issue**: #41
**Plan**: `specs/technical/41-refactor-app/plan.md`

## Tasks

- [x] T001 file_ops.zig を作成（空のモジュール）
- [x] T002 ClipboardOperation を file_ops.zig に移動
- [x] T003 isValidFilename を file_ops.zig に移動
- [x] T004 encodeBase64 を file_ops.zig に移動
- [x] T005 copyPath, copyDirRecursive を file_ops.zig に移動
- [x] T006 deletePathRecursive を file_ops.zig に移動
- [x] T007 app.zig から file_ops を import して呼び出し
- [x] T008 重複テストを file_ops.zig に移動
- [x] T009 zig build test で全テスト通過を確認
- [x] T010 手動テストで動作確認

**Status**: 10/10 完了 + Phase 2 評価完了

## 実装結果 (Phase 1 + Phase 1b)

| ファイル | 変更前 | 変更後 |
|---------|-------|-------|
| app.zig | 2253行 | 1887行 (-366行) |
| file_ops.zig | - | 390行 (新規) |

### 移動した機能

- `ClipboardOperation` enum
- `isValidFilename()` - ファイル名検証
- `encodeBase64()` - Base64 エンコード (OSC 52 用)
- `copyPath()` - ファイル/ディレクトリコピー
- `copyDirRecursive()` - 再帰コピー
- `deletePathRecursive()` - 再帰削除
- `formatDisplayPath()` - パス表示フォーマット
- `isBinaryContent()` - バイナリ判定

## Phase 2 評価結果

### search.zig 分割評価
- Search 関連: ~76行
- App state 依存: file_tree, cursor, show_hidden, input_buffer, search_matches
- **結論**: 分割メリット少、現状維持

### preview.zig 分割評価
- Preview 関連: ~60行
- App state 依存: preview_content, preview_path, preview_scroll, mode
- **結論**: 分割メリット少、現状維持

### 最終判断
app.zig 1887行は許容範囲。これ以上の分割は複雑化するため現状維持。

## 備考

- 各タスク完了後にテスト実行
- 段階的に移行（一度に全部やらない）
- 循環参照に注意
