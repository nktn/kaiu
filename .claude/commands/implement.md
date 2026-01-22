---
description: Execute implementation with Zig-specific TDD, build fixing, and code review integrated. Wraps speckit.implement with Zig agents.
---

# Zig Implementation

Orchestrator が tasks.md を読み、依存関係を分析し、タスクを並行/順次実行する。

## User Input

```text
$ARGUMENTS
```

## Process Overview

```
git checkout -b feat/<name>
   │
   ▼
tasks.md
   │
   ▼
┌─────────────────────────────────────────┐
│  Orchestrator                           │
│  ┌───────────────────────────────────┐  │
│  │  1. 依存関係分析                    │  │
│  │  2. 実行計画作成                    │  │
│  │  3. ready タスクを並行実行          │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  各タスク:                       │    │
│  │  → zig-architect (設計判断)      │    │
│  │  → zig-tdd (RED→GREEN→REFACTOR) │    │
│  │  → zig-build-resolver (エラー時) │    │
│  │  → tasks.md に [x] マーク        │    │
│  └─────────────────────────────────┘    │
│                                         │
│  完了 → 依存解決 → 次のタスク           │
└─────────────────────────────────────────┘
   │
   ▼
zig-refactor-cleaner (クリーンアップ)
   │
   ▼
/learn (パターン保存)
   │
   ▼
git commit && push → /pr → /codex → 修正 → /pr merge
```

## Execution Steps

### 1. Setup

#### 1.1 Create Feature Branch

Before starting implementation, create a feature branch:

```bash
# Branch naming: feat/<feature-name> or feat/<phase-name>
git checkout -b feat/phase1-foundation
```

This ensures:
- Clean separation from main branch
- Easy PR creation after completion
- Safe rollback if needed
- Parallel work on different features

#### 1.2 Prerequisite Check

Run prerequisite check:
```bash
.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Parse FEATURE_DIR and load:
- `tasks.md` - Task list
- `plan.md` - Architecture reference
- `spec.md` - Requirements reference

### 2. Phase Execution

For each phase in tasks.md:

#### 2.1 Design Decision (if needed)

Before coding, check if task requires structural decisions:

**Trigger zig-architect when:**
- New module/file needed
- Unclear data structure ownership
- Memory strategy choice (Arena vs GPA)
- Error set design needed
- Multiple valid approaches exist

**zig-architect outputs to `.claude/rules/architecture.md`:**
```markdown
### [2026-01-22] FileTree Memory Strategy
**Context**: FileTree nodes need allocation strategy
**Decision**: Use ArenaAllocator
**Rationale**: All nodes freed together, no individual deletes
**Alternatives**: GPA (more flexible but complex cleanup)
```

All design decisions are recorded in architecture.md for future reference.

#### 2.2 Task Execution (TDD)

For each task `- [ ] T00X ...`:

**RED** - Write failing test first:
```zig
test "task requirement" {
    // Test the expected behavior
    try testing.expectEqual(expected, actual);
}
```

Run: `zig build test` → Verify test fails

**GREEN** - Implement minimal code to pass:
- Follow task description
- Reference plan.md for structure
- Use Zig idioms (explicit allocators, error handling)

Run: `zig build test` → Verify test passes

**REFACTOR** - Improve while tests pass:
- Clean up code
- Ensure memory safety (defer/errdefer)

#### 2.3 Build Fix

If `zig build` fails:
- Invoke `zig-build-resolver` agent
- Apply minimal fixes
- Do not refactor unrelated code
- Re-run build until passing

#### 2.4 Mark Complete

Update tasks.md: `- [ ]` → `- [X]`

### 3. Refactor & Cleanup

After all tasks complete, invoke `zig-refactor-cleaner`:

#### 3.1 Analysis

```bash
# Compiler warnings
zig build 2>&1 | grep -E "warning:"

# Unused pub functions
grep -rn "pub fn " src/ | while read line; do
  # Check usage count
done
```

#### 3.2 Cleanup Actions

- **SAFE**: 未使用ローカル変数、unreachable code → 即削除
- **CAREFUL**: 未使用 pub fn → 確認後削除
- **RISKY**: API 公開関数 → 削除しない

#### 3.3 Apply Zig Idioms

- 手動クリーンアップ → defer/errdefer
- 冗長な Optional/Error 処理 → orelse/try
- 重複コード → 共通ヘルパー抽出

#### 3.4 Verification

```bash
zig build && zig build test
```

### 4. Learn (Post-Cleanup)

After cleanup complete:

Review session for extractable patterns:
- Non-obvious error fixes
- libvaxis patterns discovered
- Memory management strategies
- Build.zig patterns

Save valuable patterns to `.claude/skills/learned/`

## Agents/Skills Used

| Agent/Skill | When |
|-------------|------|
| `orchestrator` | 全体制御、依存分析、並行実行 |
| `zig-architect` | If structural decisions needed |
| `zig-tdd` | Each task (Red-Green-Refactor) |
| `zig-build-resolver` | On compilation errors |
| `zig-refactor-cleaner` | After all tasks complete (cleanup) |
| `codex` (skill) | After PR creation (code review) |

## Error Handling

- **Test fails after implementation**: Re-examine task, fix implementation
- **Build fails**: Invoke build-resolver, apply minimal fix
- **Review finds CRITICAL**: Fix before proceeding
- **Task blocked**: Note blocker, continue with parallel tasks [P]

## Progress Tracking

Report after each:
- Task: `[X] T00X completed`
- Phase: `Phase N complete (X/Y tasks)`
- Feature: `Implementation complete. Patterns saved.`

## Example Output

```
Starting implementation: Phase 1 Tree View

Phase 1: Setup
  [X] T001 Initialize Zig project
  [X] T002 Add libvaxis dependency

Phase 2: Core
  T003 Implement FileTree struct
    RED: Writing test for FileTree.init...
    GREEN: Implementing FileTree.init...
    REFACTOR: Adding errdefer for cleanup...
  [X] T003 completed

  T004 Implement directory reading
    RED: Writing test...
    BUILD ERROR: expected type 'usize', found 'u32'
    FIX: Adding @intCast
    GREEN: Test passing
  [X] T004 completed

Phase 2 Review:
  [✓] Memory safety: All allocations have defer
  [✓] Error handling: All errors propagated
  [!] MEDIUM: Consider using arena allocator

Phase 2 complete (2/2 tasks)

...

Implementation complete.
Patterns learned:
  - Saved: libvaxis-event-loop-pattern.md
```

## Post-Implementation: PR & Review

実装完了後のフロー:

### 1. Commit & Push
```bash
# Stage and commit changes
git add <files>
git commit -m "feat: <description>"

# Push branch to remote
git push -u origin feat/<feature-name>
```

### 2. PR 作成
```
/pr
```
- PR 作成（ラベル自動付与）

### 3. Codex レビュー
```
/codex このPRの変更をレビューして
```
- Codex CLI がコードレビュー実行
- 結果を PR コメントに追記

### 4. 修正方針決定
```
/pr comment 指摘1: 修正する、指摘2: 見送り（理由: ...）
```

### 5. 最終修正 & マージ
```
# 修正後
/pr merge
```

## Related

- Base: `/speckit.implement`
- Agents: `.claude/agents/zig-*.md`
- Skills: `.claude/skills/zig-build-engineer/`, `.claude/skills/codex/`
