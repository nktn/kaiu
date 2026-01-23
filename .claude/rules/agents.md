# Agent Orchestration Guide

Agent の使い分けと実行戦略。

## Available Agents

`.claude/agents/` に配置:

| Agent | 役割 | トリガー |
|-------|------|---------|
| `orchestrator` | タスク依存分析・並行実行制御 | `/implement` 実行時 |
| `zig-architect` | 設計判断・architecture.md 更新 | 構造的な決定が必要な時 |
| `zig-tdd` | RED → GREEN → REFACTOR | 各タスク実装時 |
| `zig-build-resolver` | コンパイルエラー修正 | `zig build` 失敗時 |
| `zig-refactor-cleaner` | 未使用コード削除・クリーンアップ | 全タスク完了後 |
| `speckit-task-verifier` | Task カバレッジ検証 | `/speckit.tasks` 後、実装前 |
| `speckit-impl-verifier` | 実装検証・ギャップ検出 | Phase 完了後、全タスク完了後 |

## Available Skills

`.claude/skills/` に配置:

| Skill | 役割 | 呼び出し |
|-------|------|---------|
| `codex` | コードレビュー (Codex CLI) | `/codex` |
| `zig-build-engineer` | build.zig パターン・API | 自動参照 |

## When to Use Each Agent

### Immediate Triggers (自動選択)

| 状況 | Agent |
|------|-------|
| `/implement` 実行 | `orchestrator` → 他の agent を委譲 |
| 新しいモジュール/ファイル作成 | `zig-architect` |
| struct 設計・メモリ戦略 | `zig-architect` |
| 実装タスク | `zig-tdd` |
| `zig build` エラー | `zig-build-resolver` |
| `/speckit.tasks` 後、実装前 | `speckit-task-verifier` |
| Phase 完了後 | `speckit-impl-verifier` (部分検証) |
| 全タスク完了後 | `zig-refactor-cleaner` → `speckit-impl-verifier` |
| PR 後のレビュー | `codex` (skill) |

### zig-architect Triggers

以下の場合に設計判断を依頼:

```
- 新しい .zig ファイルが必要
- データ構造の所有権が不明確
- メモリ戦略の選択 (Arena vs GPA)
- エラーセットの設計
- 複数の有効なアプローチがある
```

**出力先**: `.claude/rules/architecture.md`

### zig-tdd Triggers

全ての実装タスクで使用:

```
1. RED: 失敗するテストを書く
2. GREEN: テストを通す最小実装
3. REFACTOR: 改善 (テストは通ったまま)
```

### zig-build-resolver Triggers

コンパイルエラー発生時:

```
- 型エラー
- 未解決シンボル
- build.zig 設定問題
- 依存関係エラー
```

**原則**: 最小差分で修正、関係ないコードは触らない

### zig-refactor-cleaner Triggers

全タスク完了後に自動実行:

```
- Compiler warnings の解消
- 未使用コード (変数、関数) 削除
- 重複コードの統合
- Zig イディオム適用 (defer, orelse, try)
```

**原則**: テストが通る状態を維持、RISKY な変更はしない

### speckit-task-verifier Triggers

`/speckit.tasks` 完了後、実装前に実行:

```
- User Story 単位のカバレッジ検証
- Acceptance Criteria のタスクマッピング確認
- Priority 整合性チェック (P1 が早い Phase にあるか)
- Constitution 原則との整合性確認
```

**出力**: Coverage Matrix、Gap List、追加タスク提案

### speckit-impl-verifier Triggers

以下のタイミングで実行:

```
- Phase 完了後 (部分検証): --phase=N --story=USn
- 全タスク完了後 (最終検証): 引数なし
```

**検証項目**:
- Functional Requirements の実装確認
- Acceptance Scenarios のコードパス存在確認
- Success Criteria の検証可能性確認
- Out of Scope 機能が実装されていないか確認
- テストカバレッジ分析

**出力**: Implementation Status Matrix、Missing List、追加タスク提案

## Execution Strategy

### Parallel Execution (並行実行)

独立したタスクは並行実行:

```
# GOOD: 並行実行
Task 1.2: Directory Reading  ←┐
Task 1.3: Basic TUI          ←┴── 並行可能 (異なるファイル)

# BAD: 不要な順次実行
Task 1.2 → wait → Task 1.3
```

### Sequential Execution (順次実行)

依存関係がある場合:

```
# 順次実行が必要
Task 1.1: Project Setup
    ↓ (setup 完了後)
Task 1.2: Directory Reading (tree.zig は setup 後)
```

### Orchestrator の判断基準

```zig
fn canRunParallel(taskA: Task, taskB: Task) bool {
    // 異なるファイル && 依存関係なし → 並行可
    return !taskA.affectsFile(taskB.file) and
           !taskA.dependsOn(taskB) and
           !taskB.dependsOn(taskA);
}
```

## Multi-Agent Collaboration

### 実装フロー

```
/speckit.tasks
    │
    ▼
speckit-task-verifier (カバレッジ検証)
    │
    ├── [GAP あり] → タスク追加 → 再検証
    │
    ▼ [PASS]
orchestrator
    │
    ├── タスク分析
    │
    ├── Task A ──→ zig-architect (設計判断)
    │                   │
    │                   ▼
    │              architecture.md 更新
    │                   │
    │                   ▼
    │              zig-tdd (実装)
    │                   │
    │                   ├── [エラー] → zig-build-resolver
    │                   │
    │                   ▼
    │              完了
    │
    ├── Task B ──→ zig-tdd (並行)
    │
    ├── Phase 3 (US1) 完了 ──→ speckit-impl-verifier (部分検証)
    │                              │
    │                              ├── [GAP] → 追加タスク
    │                              │
    │                              ▼ [PASS]
    ├── Phase 4 (US2) 完了 ──→ speckit-impl-verifier (部分検証)
    │
    ▼
   全タスク完了
    │
    ▼
  zig-refactor-cleaner (クリーンアップ)
    │
    ▼
  speckit-impl-verifier (最終検証)
    │
    ├── [GAP あり] → 追加タスク → 再実装
    │
    ▼ [PASS]
  /learn (パターン保存)
    │
    ▼
   /pr
    │
    ▼
  /codex (レビュー)
```

### 設計判断の記録

zig-architect の判断は全て architecture.md に記録:

```markdown
### [2026-01-22] FileTree Memory Strategy
**Context**: FileTree nodes need allocation strategy
**Decision**: Use ArenaAllocator
**Rationale**: All nodes freed together, no individual deletes
**Alternatives**: GPA (more flexible but complex cleanup)
```

## Error Handling

### Agent 失敗時

```
1. エラー内容を記録
2. 依存タスクを blocked に変更
3. ユーザーに選択肢を提示:
   - retry: 再試行
   - skip: スキップして続行
   - abort: 中止
```

### Build Error Recovery

```
zig build 失敗
    │
    ▼
zig-build-resolver
    │
    ├── エラー分析
    ├── 最小修正適用
    ├── 再ビルド
    │
    ├── [成功] → 継続
    └── [失敗] → ユーザーに報告
```

## Best Practices

1. **Agent は単一責任**: 各 agent は一つの役割に集中
2. **設計は先に**: 実装前に zig-architect で方針決定
3. **TDD を徹底**: テストなしでコードを書かない
4. **最小修正**: build-resolver は関係ないコードを触らない
5. **記録を残す**: 設計判断は architecture.md に蓄積
6. **並行実行を活用**: 独立タスクは並行で効率化

## Decision Log

レビュー指摘を採用/スキップする際は、PR コメントに Decision Log を残す。

### Format

```markdown
## Decision Log

### [指摘内容] (Severity - 採用/スキップ)

**Issue**: 何が指摘されたか
**Decision**: どうするか
**Rationale**: なぜその判断か
**Alternatives considered**: 他に検討した選択肢
```

### Purpose

- 意思決定の経緯を記録
- 後から「なぜこうなった？」を追跡可能に
- レビュアーとの認識合わせ
