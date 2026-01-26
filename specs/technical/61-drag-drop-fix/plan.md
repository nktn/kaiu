# Technical Plan: Finder Drag & Drop Fix

## Issue Reference
- #61: bug: Finder からのドラッグ&ドロップが動作しない (Ghostty)

## Overview

Finder からファイルをドラッグ&ドロップしても何も起きない問題を修正する。

## 現状の実装

```
setBracketedPaste(true)
    ↓
paste_start イベント
    ↓
paste_buffer に蓄積
    ↓
paste_end イベント
    ↓
handlePastedContent() でパス検出
    ↓
handleFileDrop() でコピー
```

## 調査ポイント

1. **Ghostty の挙動確認**
   - `cat` で Finder からドラッグ → パスが表示されるか？
   - Bracketed paste を使っているか？

2. **libvaxis の paste イベント**
   - `paste_start` / `paste_end` が発火しているか？
   - 通常のキー入力として来ている可能性は？

3. **ファイルパス形式**
   - Finder が送信するパスの形式 (`file://` prefix? スペースエスケープ?)

## 可能性のある原因

| 原因 | 対応 |
|------|------|
| Ghostty が bracketed paste を使わない | 通常入力からパスを検出 |
| `paste_start` イベントが来ない | デバッグログ追加 |
| パス形式が違う (`file://` 等) | パース処理を修正 |
| スペースがエスケープされている | unescape 処理を追加 |

## 修正方針

1. デバッグ情報をステータスバーに表示
2. 原因を特定
3. 対応を実装
