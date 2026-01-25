# Technical Tasks: Preserve expanded directory state during tree reload

**Issue**: #17
**Plan**: `specs/technical/17-preserve-expanded-state/plan.md`

## Tasks

- [x] T001 現在の展開/折りたたみ実装を確認 `src/app.zig`, `src/tree.zig`
- [x] T002 `expanded_paths: StringHashMap(void)` を App に追加
- [x] T003 展開時に `expanded_paths` にパスを追加
- [x] T004 折りたたみ時に `expanded_paths` からパスを削除
- [x] T005 リロード後に `expanded_paths` を参照して展開を復元
- [x] T006 `zig build test` で全テスト通過を確認
- [ ] T007 手動テストで動作確認
  - 深いディレクトリを展開 → `R` キーでリロード → 展開状態が保持されることを確認
  - ファイル操作（paste など）後 → 展開状態が保持されることを確認

**Status**: 6/7 完了

## 備考

- Feature Track と異なり spec.md は作成しない (Issue が仕様書の役割)
- マージ前に tasks.md を更新すること (Issue #35)
