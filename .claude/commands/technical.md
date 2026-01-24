---
description: Technical Track 実装。リファクタリング、ドキュメント改善など開発者価値の作業を Issue ベースで実行する。
---

# Technical Track Implementation

## User Input

```text
$ARGUMENTS
```

**入力形式**:
- `/technical "改善の説明"` - 新規 Issue を作成して開始
- `/technical #22` - 既存 Issue を参照して開始

---

## Agent Architecture

```
/technical
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Issue Analysis & Task Planning                    │
│  ├── 入力を解析 (新規 or 既存 Issue)                          │
│  ├── 関連 Issue を収集・分析                                  │
│  ├── タスクを整理し Issue の「タスク」セクションに書き込み       │
│  └── Branch 作成 (未作成の場合)                               │
│                                                             │
│  Phase 2: User Approval                                     │
│  └── タスク一覧を表示してユーザー承認を待つ                     │
│                                                             │
│  Phase 3: Execution (承認後)                                │
│  │  orchestrator が Issue タスクを実行:                       │
│  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐│
│  │  │zig-architect│ → │  zig-tdd    │ → │zig-build-resolver││
│  │  │ 設計判断     │   │ RED→GREEN  │   │ (失敗時のみ)     ││
│  │  └─────────────┘   └─────────────┘   └─────────────────┘│
│  │                                                          │
│  Phase 4: Completion                                        │
│  │  ┌─────────────────────┐   ┌─────────────┐              │
│  │  │zig-refactor-cleaner │ → │ doc-updater │              │
│  │  │ リファクタリング      │   │ ドキュメント │              │
│  │  └─────────────────────┘   └─────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

**Feature Track との違い**:
- spec.md を使わない (Issue の「タスク」セクションを使用)
- speckit-task-verifier をスキップ
- speckit-impl-verifier をスキップ

---

## Execution Steps

### Step 1: 入力解析

```
入力: $ARGUMENTS

パターン A: "#22" または "#22 追加説明"
  → 既存 Issue #22 を参照
  → gh issue view 22 で内容を取得

パターン B: "改善の説明文"
  → 新規 Issue を作成予定
  → 関連する既存 Issue を検索して提案
```

---

### Step 2: 関連 Issue 収集

```bash
# technical ラベルの Issue を取得
gh issue list --label technical --state open --json number,title,body

# 関連キーワードで検索
gh issue list --search "keyword" --state open
```

**ユーザーに確認**:
```
関連する Issue が見つかりました:
- #21: docs: clarify separation between architecture.md and learned/
- #19: Surface partial failures in paste operations

これらを統合して進めますか？
```

---

### Step 3: タスク整理

既存 Issue のタスクを分析し、整理する:

```markdown
## タスク (Issue に書き込む)

### 分析結果
- Issue #22 から: 5 タスク
- Issue #21 から: 2 タスク (関連として統合)

### 実行タスク
- [ ] workflow.md に Track 説明を追加
- [ ] /technical skill を作成
- [ ] /speckit.specify を更新
- [ ] constitution.md に判断基準を追加
- [ ] ...

このタスクリストで進めていいですか？
```

**ユーザー承認を待つ** (承認までコードを書かない)

---

### Step 4: Branch 作成

```bash
# 現在のブランチを確認
git branch --show-current

# main なら新しいブランチを作成
if [ "$(git branch --show-current)" = "main" ]; then
    git checkout -b technical/{issue-number}-{short-description}
fi
```

**Branch 命名規則**: `technical/{issue-number}-{short-description}`
例: `technical/22-workflow-track-separation`

---

### Step 5: Orchestrator 起動 (Technical Track Mode)

```
Task(subagent_type: "orchestrator", prompt: "
Technical Track モードで実行してください。

■ 参照 Issue: #{issue-number}
■ タスク:
{Issue のタスクセクション}

Phase 1: 各タスクを実行
- zig-architect → zig-tdd → (失敗時のみ) zig-build-resolver

Phase 2: Completion
- zig-refactor-cleaner
- doc-updater

**注意**:
- spec.md は参照しない
- speckit-impl-verifier はスキップ
")
```

---

## 計画出力フォーマット

```
=== Technical Track 実行計画 ===

■ 参照 Issue
- #22: workflow: clarify Feature Track vs Technical Track separation

■ 関連 Issue
- #21: docs: clarify separation between architecture.md and learned/

■ タスク一覧

Task 1: workflow.md に Track 説明を追加
  ├── 変更ファイル: .claude/rules/workflow.md
  └── Agent: zig-architect → (コードなしなら skip)

Task 2: /technical skill を作成
  ├── 変更ファイル: .claude/commands/technical.md
  └── Agent: zig-architect

Task 3: constitution.md に判断基準を追加
  ├── 変更ファイル: specs/constitution.md
  └── Agent: zig-architect → (コードなしなら skip)

■ 完了後
  ├── zig-refactor-cleaner (コード変更がある場合)
  └── doc-updater

=== この計画で進めていいですか？ ===
```

---

## Agent Calls

### zig-architect (設計判断がある場合)

```
Task(subagent_type: "zig-architect", prompt: "
タスク: [タスク名]
内容: [タスクの説明]

設計判断を行い、architecture.md に記録してください。
")
```

### zig-tdd (コード変更がある場合)

```
Task(subagent_type: "zig-tdd", prompt: "
タスク: [タスク名]
設計: [zig-architect の出力]

TDD サイクルを実行してください。
")
```

### zig-build-resolver (ビルド失敗時のみ)

```
Task(subagent_type: "zig-build-resolver", prompt: "
zig build でエラーが発生しました。
最小限の修正で解決してください。
")
```

### zig-refactor-cleaner (コード変更後)

```
Task(subagent_type: "zig-refactor-cleaner", prompt: "
タスク完了後のクリーンアップ:
1. 未使用コード削除
2. Zig イディオム適用
3. テスト成功確認
")
```

### doc-updater

```
Task(subagent_type: "doc-updater", prompt: "
Technical Track 完了後の処理:
1. ドキュメント更新 (README.md, architecture.md, workflow.md)
2. パターン学習・保存
")
```

---

## Completion Checklist

- [ ] Issue のタスクが全て `[x]` になっている
- [ ] `zig build` 成功 (コード変更がある場合)
- [ ] `zig build test` 成功 (コード変更がある場合)
- [ ] ドキュメントが更新されている

---

## Post-Implementation

### 1. PR 作成

```bash
/pr
# Body に "Closes #22" を含める → マージ時に Issue も自動クローズ
```

### 2. コードレビュー

```
/codex-fix
# レビュー → 修正 → Decision Log → 再レビュー
```

### 3. 手動テスト & マージ

マージすると関連 Issue も自動クローズ。

---

## Issue Template (新規作成時)

```markdown
## 概要
[改善の説明]

## 背景
[なぜ必要か]

## 方針
[どう実現するか]

## 関連 Issue
- #XX (統合/参照する Issue)

## タスク
- [ ] タスク1
- [ ] タスク2
- [ ] ...
```

---

## Agent Reference

| Agent | 役割 | 条件 |
|-------|------|------|
| `zig-architect` | 設計判断 | 設計が必要な場合 |
| `zig-tdd` | TDD サイクル | コード変更がある場合 |
| `zig-build-resolver` | ビルド修正 | ビルド失敗時のみ |
| `zig-refactor-cleaner` | クリーンアップ | コード変更後 |
| `doc-updater` | ドキュメント更新 | 常に実行 |

**Feature Track との違い**:
- `speckit-task-verifier`: スキップ
- `speckit-impl-verifier`: スキップ
- `orchestrator`: Issue タスクベースで動作
