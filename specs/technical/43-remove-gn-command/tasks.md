# Technical Tasks: gn (go to path) コマンドを削除

**Issue**: #43
**Plan**: `specs/technical/43-remove-gn-command/plan.md`

## Tasks

- [x] T001 app.zig から path_input 関連コードを削除
- [x] T002 ui.zig から gn ヒントを削除
- [x] T003 README.md から gn キーバインドを削除
- [x] T004 architecture.md から path_input 状態を削除
- [x] T005 zig build test で全テスト通過を確認
- [x] T006 手動テストで動作確認（Codex レビュー完了）

**Status**: 6/6 完了

## 備考

- Issue #41 (app.zig リファクタリング) の前に実施
- 削除により約100行のコード削減
