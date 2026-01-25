# Tasks: Codex Review Findings (PR #27)

Issue: #32

## Phase 1: HIGH Priority

### T001: Symlink handling in copyDirRecursive

- [ ] `copyDirRecursive` で symlink を保存してコピーする実装
  - symlink ターゲットを `readLink` で取得
  - `std.posix.symlink` で新しい symlink を作成
- [ ] テスト追加: symlink を含むディレクトリのコピーが正しく動作することを確認

## Phase 2: MEDIUM Priority

### T002: Suffix limit error handling

- [ ] suffix > 100 時に `error.TooManyConflicts` を返すように変更
- [ ] paste 時に適切なエラーメッセージ ("Too many file conflicts") を表示
- [ ] テスト追加: 大量の衝突時のエラー処理を確認

## Phase 3: LOW Priority

### T003: Search mode stale counts

- [ ] `enterSearchMode` で `search_matches` と `current_match` をクリア
- [ ] テスト追加: 検索モード開始時の状態リセットを確認

### T004: ESC key behavior

- [ ] ESC キー動作を修正
  - マークあり時: ESC でマーククリア
  - 検索アクティブ時: ESC で検索クリア
  - 両方ある時: ESC でマークをクリア (検索は残る)
- [ ] ヒント表示を実際の動作に合わせる
- [ ] テスト追加: ESC キー動作の各シナリオを確認

## 完了条件

- [ ] `zig build` 成功
- [ ] `zig build test` 成功
- [ ] 全てのタスクが完了
