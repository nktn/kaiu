# Tasks: Finder Drag & Drop Fix

## Reference
- Issue: #61
- Plan: [plan.md](./plan.md)

## Phase 1: 調査

### T001: Ghostty でのドラッグ動作を確認
- `cat` コマンドで Finder からドラッグ → パスが正しく表示される
- **Status**: [x] Done

### T002: paste イベントのデバッグ
- `paste_start` / `paste_end` が発火している
- 問題: ASCII のみ処理していた（日本語が欠落）
- **Status**: [x] Done

## Phase 2: 修正

### T003: 原因に応じた修正を実装
- UTF-8 エンコード処理を追加（codepoint → UTF-8 bytes）
- バックスラッシュエスケープ解除処理を追加（`\ ` → ` `）
- カーソル位置のディレクトリにドロップするよう修正
- **Status**: [x] Done

## Phase 3: 検証

### T004: 手動テスト
- Finder からファイルをドラッグ → コピーされる ✓
- カーソル位置のディレクトリにコピーされる ✓
- **Status**: [x] Done

## Known Limitations

### 日本語ファイル名が動作しない
- **原因**: libvaxis の bracketed paste 実装の制限
- libvaxis が UTF-8 マルチバイト文字を個別の codepoint に分解する際、一部の文字が U+FFFD (replacement character) になる
- **関連 Issue**: [bemenu #410](https://github.com/Cloudef/bemenu/issues/410) - 同様の問題
- **回避策**: 英語ファイル名のみ対応。日本語ファイルは kaiu 内の yank/paste (y/p) を使用

## Progress

| Phase | Tasks | Done | Status |
|-------|-------|------|--------|
| 1 | 2 | 2 | Done |
| 2 | 1 | 1 | Done |
| 3 | 1 | 1 | Done |
| **Total** | **4** | **4** | **100%** |
