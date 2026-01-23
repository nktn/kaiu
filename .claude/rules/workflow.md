# SpecKit + Implement ワークフロー

kaiu 開発における計画から実装までの全体フロー。

---

## 概要図

```
┌─────────────────────────────────────────────────────────────────┐
│                      計画フェーズ                                │
│                                                                 │
│  /speckit.specify → /speckit.plan → /speckit.tasks             │
│                                          │                      │
│                                          ▼                      │
│                               /speckit.task-verify              │
│                                          │                      │
│                          [GAP] ←─────────┼──────────→ [PASS]   │
│                            │                            │       │
│                            ▼                            ▼       │
│                    タスク追加して再検証          tasks.md 完成   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼ (別セッション/別タイミング)
┌─────────────────────────────────────────────────────────────────┐
│                      実装フェーズ                                │
│                                                                 │
│  /implement                                                     │
│      │                                                          │
│      ▼                                                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ orchestrator                                               │ │
│  │                                                            │ │
│  │ Phase 1: Planning                                          │ │
│  │   └── タスク分析 → 計画出力 → ユーザー承認待ち              │ │
│  │                                                            │ │
│  │ Phase 2: Execution (承認後)                                │ │
│  │   ├── 各タスク:                                            │ │
│  │   │   zig-architect → zig-tdd → zig-build-resolver        │ │
│  │   │                                                        │ │
│  │   └── Phase 完了ごと:                                      │ │
│  │       speckit-impl-verifier (部分検証)                     │ │
│  │           └── [GAP] → 追加タスク                           │ │
│  │                                                            │ │
│  │ Phase 3: Completion                                        │ │
│  │   ├── zig-refactor-cleaner (クリーンアップ)                │ │
│  │   └── speckit-impl-verifier (最終検証)                     │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│      │                                                          │
│      ▼ [検証 PASS]                                              │
│  doc-updater (ドキュメント更新 + パターン学習)                   │
│      │                                                          │
│      ▼                                                          │
│  /pr → /codex                                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 計画フェーズ詳細

### 1. /speckit.specify

機能仕様を作成。

**出力**: `.specify/specs/<feature>/spec.md`

**内容**:
- User Stories (US1, US2, ...) + Priority (P1, P2, P3)
- Acceptance Criteria (AC)
- Functional Requirements (FR)
- Success Criteria (SC)
- Out of Scope

### 2. /speckit.plan

技術設計を作成。

**出力**: `.specify/specs/<feature>/plan.md`

**内容**:
- Tech Stack
- Architecture
- Data Model
- Implementation Strategy

### 3. /speckit.tasks

タスクリストを生成。

**出力**: `.specify/tasks/<feature>/tasks.md`

**内容**:
- Phase 1: Setup
- Phase 2: Foundational
- Phase 3+: User Story ごと
- Final Phase: Polish

### 4. /speckit.task-verify

タスクカバレッジを検証。

**検証項目**:
- 全 User Story にタスクがあるか
- 全 Acceptance Criteria がカバーされているか
- Priority 整合性 (P1 が早い Phase にあるか)

**出力**: Coverage Matrix、Gap List

---

## 実装フェーズ詳細

### 1. /implement → orchestrator

**Phase 1: Planning**
- tasks.md を分析
- 実行計画を出力
- **ユーザー承認を待つ** (承認までコードを書かない)

**Phase 2: Execution**

各タスクで 3 つの Agent を順番に呼び出し:

| Agent | 役割 |
|-------|------|
| `zig-architect` | 設計判断、architecture.md 更新 |
| `zig-tdd` | RED → GREEN → REFACTOR |
| `zig-build-resolver` | ビルドエラー修正 |

Phase 完了ごとに `speckit-impl-verifier` で部分検証。

**Phase 3: Completion**
- `zig-refactor-cleaner`: 未使用コード削除、イディオム適用
- `speckit-impl-verifier`: 最終検証

### 2. doc-updater

**ドキュメント更新**:
- README.md (キーバインド表)
- architecture.md (状態遷移図)

**パターン学習**:
- セッションから有用なパターンを抽出
- `.claude/skills/learned/` に保存

### 3. /pr → /codex

- `/pr`: Pull Request 作成
- `/codex`: コードレビュー

---

## Agent 一覧

| Agent | 役割 | 呼び出しタイミング |
|-------|------|------------------|
| `orchestrator` | タスク管理・実行制御 | `/implement` 開始時 |
| `zig-architect` | 設計判断 | 各タスクの最初 |
| `zig-tdd` | TDD サイクル | 設計判断後 |
| `zig-build-resolver` | ビルド修正 | TDD 後 |
| `zig-refactor-cleaner` | リファクタリング | 全タスク完了後 |
| `speckit-task-verifier` | Task カバレッジ検証 | `/speckit.tasks` 後 |
| `speckit-impl-verifier` | 実装検証 | Phase 完了後、最終 |
| `doc-updater` | ドキュメント + 学習 | 検証 PASS 後 |

---

## コマンド一覧

### 計画系 (/speckit.*)

| コマンド | 役割 |
|----------|------|
| `/speckit.specify` | 仕様作成 |
| `/speckit.clarify` | 仕様の曖昧点を質問 |
| `/speckit.plan` | 技術設計 |
| `/speckit.tasks` | タスク生成 |
| `/speckit.task-verify` | タスクカバレッジ検証 |
| `/speckit.analyze` | 一貫性分析 |
| `/speckit.impl-verify` | 実装検証 |

### 実装系

| コマンド | 役割 |
|----------|------|
| `/implement` | 実装実行 (orchestrator 起動) |
| `/build-fix` | ビルドエラー修正 |
| `/tdd` | TDD サイクル |

### その他

| コマンド | 役割 |
|----------|------|
| `/pr` | Pull Request 作成 |
| `/codex` | コードレビュー |

---

## 典型的な開発フロー例

```bash
# 1. 計画フェーズ (セッション A)
/speckit.specify "検索機能を追加したい"
/speckit.plan
/speckit.tasks
/speckit.task-verify
# → tasks.md 完成、GAP なし

# 2. 実装フェーズ (セッション B)
/implement
# → orchestrator が計画出力
# → "この計画で進めていいですか？" → はい
# → 各タスク実行...
# → 最終検証 PASS
# → doc-updater 実行

# 3. PR 作成
/pr
/codex
```
