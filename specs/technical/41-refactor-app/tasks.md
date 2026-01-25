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

**Status**: 10/10 完了

## 実装結果

| ファイル | 変更前 | 変更後 |
|---------|-------|-------|
| app.zig | 2253行 | 1983行 (-270行) |
| file_ops.zig | - | 300行 (新規) |

### 移動した機能

- `ClipboardOperation` enum
- `isValidFilename()` - ファイル名検証
- `encodeBase64()` - Base64 エンコード (OSC 52 用)
- `copyPath()` - ファイル/ディレクトリコピー
- `copyDirRecursive()` - 再帰コピー
- `deletePathRecursive()` - 再帰削除

### 残留機能 (Phase 2 で検討)

marking/yank/cut/paste/rename/new file/new dir/delete の mode handler は
App state (input_buffer, mode, status_message) と密結合のため app.zig に残留。
これらは App のメソッドから file_ops の関数を呼び出す形で利用。

## 備考

- 各タスク完了後にテスト実行
- 段階的に移行（一度に全部やらない）
- 循環参照に注意
