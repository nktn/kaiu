# Tasks: Codex Review Findings (PR #27)

Issue: #32

## Status: Complete

## Phase 1: HIGH Priority

### T001: Symlink handling in copyDirRecursive

- [x] `copyDirRecursive` で symlink を保存してコピーする実装
  - symlink ターゲットを `readLink` で取得
  - `std.posix.symlink` で新しい symlink を作成
- [x] テスト追加: symlink を含むディレクトリのコピーが正しく動作することを確認

## Phase 2: MEDIUM Priority

### T002: Suffix limit error handling

- [x] suffix > 100 時にファイルをスキップしてデータロスを防ぐ
  - `break` を `continue` に変更して上書きを防止
  - fail_count に含まれてステータスに表示される

## Phase 3: LOW Priority

### T003: Search mode stale counts

- [x] `enterSearchMode` で `search_matches` と `current_match` をクリア

### T004: ESC key behavior

- [x] ESC キー動作を修正
  - マークあり時: ESC でマーククリア
  - 検索アクティブ時: ESC で検索クリア
  - 両方ある時: ESC でマークをクリア (検索は残る)
- [x] ヒント表示を実際の動作に合わせる (マーク優先)

## 完了条件

- [x] `zig build` 成功
- [x] `zig build test` 成功
- [x] 全てのタスクが完了
