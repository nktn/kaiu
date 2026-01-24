# Technical Plan: Surface partial failures in paste operations

- **Issue**: #19
- **Branch**: `technical/19-partial-paste-failures`
- **Created**: 2026-01-25

## 概要

ペースト操作で複数ファイルを処理する際、一部が失敗しても現在は「Pasted」と表示される。
ユーザーに部分的な失敗を明示的に伝えるよう改善する。

## 背景

- 現在の実装: エラーは `catch { continue; }` で無視され、1つでも成功すれば「Pasted」
- Codex review Round 3 で指摘 (PR #16 Decision Log で defer)
- ユーザーは失敗に気づかず、ファイルが欠落する可能性がある

## 方針

PR #16 の undo エラーハンドリングパターンを参考に、成功/失敗カウントを追跡してステータスメッセージに反映する。

**ステータスメッセージ**:
- 全成功: `"Pasted N files"`
- 部分成功: `"Pasted N files (M failed)"`
- 全失敗: `"Paste failed"`

## 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/app.zig` | `performPaste()` 関数のエラーハンドリング改善 |

### 影響を受けるコンポーネント

- ペースト操作 (`p` キー)
- ステータスバー表示

## 設計判断

### 判断1: ステータスメッセージのフォーマット

**選択肢**:
- A: `"Pasted N files (M failed)"` - シンプルで明確
- B: `"Pasted N/M files"` - 分数表記
- C: `"Pasted N files, M errors"` - より詳細

**決定**: A (`"Pasted N files (M failed)"`)

**理由**: undo 実装と一貫性があり、問題があることを括弧内で示す

### 判断2: 失敗詳細の表示

**選択肢**:
- A: ステータスメッセージのみ (詳細なし)
- B: ログに失敗ファイル名を出力
- C: 別ペインで失敗リストを表示

**決定**: A (ステータスメッセージのみ)

**理由**: MVP として最小限の変更。詳細表示は別 Issue で検討

## リスク・懸念事項

- 特になし (既存パターンの適用)

## 参照

- Issue: #19
- 関連 PR: #16 (undo エラーハンドリング)
