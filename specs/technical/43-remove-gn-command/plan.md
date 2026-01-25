# Technical Plan: gn (go to path) コマンドを削除

- **Issue**: #43
- **Branch**: `technical/43-remove-gn-command`
- **Created**: 2026-01-25

## 概要

`gn` コマンド（パス入力による移動機能）を削除し、コードを簡素化する。

## 背景

1. VS Code のファイル一覧にない機能
2. cwd 不一致問題（終了時に元の場所に戻る）
3. 使用頻度が低く、複雑さのコストに見合わない

## 削除対象

| 対象 | ファイル | 行数（概算） |
|------|---------|-------------|
| `AppMode.path_input` | app.zig | 1行 |
| `enterPathInputMode()` | app.zig | 5行 |
| `navigateToInputPath()` | app.zig | 50行 |
| `handlePathInputKey()` | app.zig | 30行 |
| gn キーバインド | app.zig | 3行 |
| path_input 分岐 | app.zig | 複数箇所 |
| UI ヒント | ui.zig | 1行 |

**合計**: 約100行削減

## 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/app.zig` | path_input 関連コード削除 |
| `src/ui.zig` | gn ヒント削除 |
| `README.md` | gn キーバインド削除 |
| `architecture.md` | 状態遷移図から path_input 削除 |

## 参照

- Issue: #43
- 関連 Issue: #41 (app.zig リファクタリング)
