# Technical Plan: Update documentation before merging PR

- **Issue**: #35
- **Branch**: `technical/35-pre-merge-docs`
- **Created**: 2026-01-25

## 概要

PR マージ前にドキュメントを更新するワークフローを確立し、追加 PR の発生を防ぐ。

## 背景

- PR #27 マージ後に tasks.md を更新しようとして追加 PR #34 が必要になった
- main への直接 push が禁止されているため、マージ後の軽微な更新も PR が必要
- 事前に更新すれば 1 PR で完結できる

## 方針

1. **workflow.md にマージ前チェックを追加**
   - PR 作成後、マージ前に確認すべきドキュメントのリスト

2. **Technical Track の tasks.md フォーマット簡素化**
   - Phase 構造を廃止
   - シンプルなタスクリストと Status 行のみ

3. **PR テンプレート（オプション）**
   - .github/pull_request_template.md にチェックリストを追加
   - 今回はスキップ（必要に応じて後で追加）

## 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `.claude/rules/workflow.md` | マージ前チェックセクションを追加 |
| `.specify/templates/technical-tasks-template.md` | Phase 構造を廃止、シンプル化 |

## 設計判断

### 判断1: チェックリストの配置場所

**選択肢**:
- A: workflow.md に追加
- B: 別ファイル（pre-merge-checklist.md）を作成
- C: PR テンプレートに追加

**決定**: A（workflow.md に追加）

**理由**: 既存のワークフロー文書に統合することで参照しやすい

### 判断2: Technical Track tasks.md のフォーマット

**現状**:
```markdown
## Phase 1: 準備
- [x] T001 ...

## 進捗
| Phase | タスク数 | 完了 | 進捗率 |
```

**提案**:
```markdown
## Tasks
- [x] T001 ...
- [x] T002 ...

**Status**: 2/2 完了
```

**決定**: 提案形式を採用

**理由**: Technical Track は通常小規模で Phase 分けは過剰

## 参照

- Issue: #35
- 関連 PR: #27, #34 (Issue #19 関連)
