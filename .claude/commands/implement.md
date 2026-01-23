---
description: Execute implementation with Zig-specific TDD, build fixing, and code review integrated. Orchestrator が計画を立て、承認後に各 Agent を呼び出す。
---

# Zig Implementation

## User Input

```text
$ARGUMENTS
```

## Agent Architecture

```
/implement
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  orchestrator (タスク管理 Agent)                             │
│                                                             │
│  Phase 1: Planning                                          │
│  ├── specs/*.md 確認                                        │
│  ├── 計画出力（各タスクの Agent 呼び出しを明示）               │
│  └── ユーザー承認待ち ← **承認までコードを書かない**           │
│                                                             │
│  Phase 2: Execution (承認後)                                │
│  │  各タスクに対して以下の Agent を順番に実行:                │
│  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐│
│  │  │zig-architect│ → │  zig-tdd    │ → │zig-build-resolver││
│  │  │ 設計判断     │   │ RED→GREEN  │   │ ビルド確認       ││
│  │  └─────────────┘   └─────────────┘   └─────────────────┘│
│  │                                                          │
│  Phase 3: Completion                                        │
│  │  ┌─────────────────────┐                                 │
│  │  │zig-refactor-cleaner │                                 │
│  │  │ リファクタリング      │                                 │
│  │  └─────────────────────┘                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Execution Steps

### Step 1: Setup

```bash
git checkout -b feat/<feature-name>
```

---

### Step 2: Orchestrator 起動 (MANDATORY)

**orchestrator Agent を呼び出す:**

```
Task(subagent_type: "orchestrator", prompt: "
.specify/tasks/ 配下のタスクを実行してください。

Phase 1: Planning
1. .specify/specs/*.md を確認
2. 実行計画を出力（各タスクで呼び出す Agent を明示）
3. ユーザー承認を待つ（承認までコードを書かない）

Phase 2: Execution (承認後)
各タスクで以下の Agent を必ず呼び出す:
- zig-architect
- zig-tdd
- zig-build-resolver

Phase 3: Completion
- zig-refactor-cleaner
")
```

---

## 計画出力フォーマット (orchestrator が出力)

```
=== 実行計画 ===

■ 関連 Spec
- specs/*.md (該当する spec を列挙)

■ タスク一覧と Agent 呼び出し

Task 1.1: Project Setup
  ├── 変更ファイル: build.zig, build.zig.zon
  ├── 変更内容: プロジェクト初期化
  ├── 影響範囲: なし
  └── Agent: zig-architect → zig-tdd → zig-build-resolver

Task 1.2: Directory Reading
  ├── 変更ファイル: src/tree.zig
  ├── 変更内容: FileTree 実装
  ├── 影響範囲: なし
  └── Agent: zig-architect → zig-tdd → zig-build-resolver

... (全タスク)

■ 全タスク完了後
  └── zig-refactor-cleaner

=== この計画で進めていいですか？ ===
```

**承認があるまでコードを書かない。**

---

## Agent Calls (orchestrator が実行)

### 各タスクで呼び出す Agent (MANDATORY)

#### 1. zig-architect

```
Task(subagent_type: "zig-architect", prompt: "
タスク: [タスク名]
内容: [タスクの説明]

設計判断を行い、architecture.md に記録してください。
")
```

#### 2. zig-tdd

```
Task(subagent_type: "zig-tdd", prompt: "
タスク: [タスク名]
設計: [zig-architect の出力を参照]

TDD サイクルを実行:
1. RED: 失敗するテストを書く
2. GREEN: 最小限のコードで通す
3. テスト成功を確認
")
```

#### 3. zig-build-resolver

```
Task(subagent_type: "zig-build-resolver", prompt: "
zig build と zig build test を実行。
エラーがあれば修正、なければ「ビルド成功」と報告。
")
```

#### 4. タスク完了マーク

```
tasks.md を更新:
- [ ] Task description  →  - [x] Task description
```

---

### 全タスク完了後 (MANDATORY)

#### zig-refactor-cleaner

```
Task(subagent_type: "zig-refactor-cleaner", prompt: "
全タスクが完了しました。
1. Compiler warnings 確認・修正
2. 未使用コード削除
3. 重複コード統合
4. Zig イディオム適用
5. 全テスト成功を確認
")
```

---

## Completion Checklist

- [ ] 全タスクに `[x]` がついている
- [ ] architecture.md に設計判断が記録されている
- [ ] `zig build` 成功
- [ ] `zig build test` 成功
- [ ] `/speckit.impl-verify` で実装検証 PASS

---

## Post-Implementation

### 1. 実装検証 (RECOMMENDED)

```
/speckit.impl-verify
```

spec.md の要件が実装されているか最終確認。
ギャップがあれば追加タスクを提案。

### 2. ドキュメント更新 & パターン学習

```
Task(subagent_type: "doc-updater", prompt: "
実装完了後の処理:
1. ドキュメント更新 (README.md, architecture.md)
2. セッションからパターン抽出・保存
")
```

### 3. コミット & PR

```bash
git add <files>
git commit -m "feat: <description>"
git push -u origin feat/<feature-name>
```

```
/pr              # PR 作成
/codex レビュー   # コードレビュー
```

---

## Agent Reference

| Agent | 役割 | いつ |
|-------|------|------|
| `orchestrator` | タスク管理、計画立案、承認待ち | 最初に呼び出し |
| `zig-architect` | 設計判断、architecture.md 更新 | 各タスクの最初 |
| `zig-tdd` | TDD サイクル (RED→GREEN) | 設計判断後 |
| `zig-build-resolver` | ビルド確認/修正 | TDD 後 |
| `zig-refactor-cleaner` | リファクタリング | 全タスク完了後 |

**すべての Agent は MANDATORY（必須）。スキップしない。**

---

## Agent Files

- `.claude/agents/orchestrator.md`
- `.claude/agents/zig-architect.md`
- `.claude/agents/zig-tdd.md`
- `.claude/agents/zig-build-resolver.md`
- `.claude/agents/zig-refactor-cleaner.md`
