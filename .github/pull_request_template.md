## Summary

<!-- 変更内容を1-3行で説明 -->

## Related Issue

<!-- Closes #XX または Refs #XX -->

## Changes

<!-- 主な変更点をリスト -->

-

## Pre-merge Checklist

### 必須

- [ ] `tasks.md` の Status を更新済み（完了率 100%）
- [ ] `git status` が clean（未コミットの変更なし）
- [ ] `zig build test` が通る（コード変更がある場合）

### 該当する場合

- [ ] キーバインド追加/変更 → `README.md` を更新
- [ ] 新機能追加 → `README.md` の機能一覧を更新
- [ ] AppMode 追加/変更 → `architecture.md` の状態遷移図を更新
- [ ] Agent/コマンド追加 → `workflow.md` の一覧を更新

## Test Plan

<!-- テスト方法や確認した項目 -->

- [ ] `zig build test` が通る
- [ ] 手動テストで動作確認
