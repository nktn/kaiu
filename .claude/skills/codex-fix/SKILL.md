---
name: codex-fix
description: >
  /codex-fix - Codex レビュー修正ループ
triggers:
  - "/codex-fix"
  - "codex fix"
  - "レビュー修正"
---

# Codex Fix

Codex レビューと修正を自動でループ実行するスキル。

## 概要

1. Codex CLI でレビュー実行
2. 指摘を解析
3. 各指摘の修正方針をユーザーに提示
4. 承認された修正を適用
5. コミット
6. 再レビュー
7. 指摘がなくなるまで繰り返し

## 実行手順

### Step 1: 初回レビュー

```bash
codex exec --full-auto --sandbox read-only --cd <project_directory> "Review the changes in this PR for code quality issues. For each issue found, provide: severity (HIGH/MEDIUM/LOW), file path, line number, issue description, and suggested fix."
```

### Step 2: 指摘を解析

レビュー結果から指摘を抽出:

```yaml
issues:
  - severity: HIGH
    file: src/app.zig
    line: 42
    issue: "Memory leak"
    suggestion: "Add errdefer"
```

### Step 3: ユーザー承認

各指摘について修正方針を提示:

```
=== 指摘 1/3 ===
File: src/app.zig:42
Issue: Memory leak - allocated memory not freed on error path
Severity: HIGH

修正方針:
- errdefer allocator.free(data) を追加

[Y] 適用  [N] スキップ  [E] 編集して適用  [A] 全て適用
```

### Step 4: 修正適用

承認された修正を `codex-fixer` Agent で適用:

```bash
# Task tool で codex-fixer Agent を呼び出し
```

### Step 5: コミット

```bash
git add <modified files>
git commit -m "fix: address codex review feedback (round N)"
```

### Step 6: 再レビュー

```bash
codex exec --full-auto --sandbox read-only --cd <project_directory> "Review the changes for remaining issues"
```

### Step 7: ループ判定

- 指摘が 0 件 → Step 8 へ
- 最大ラウンド数 → Step 8 へ
- 指摘あり → Step 2 へ

### Step 8: PR コメントに Decision Log を追記

ループ完了後、意思決定の記録を PR コメントに追記:

```bash
gh pr comment <PR番号> --body "<Decision Log>"
```

**Decision Log フォーマット**:

```markdown
## Codex Review & Fix - Decision Log

### Round 1
| Issue | Severity | Decision | Rationale |
|-------|----------|----------|-----------|
| Memory leak in app.zig:42 | HIGH | ✅ Fixed | errdefer 追加 |
| Unused variable in ui.zig:15 | LOW | ⏭️ Skipped | 将来使用予定 |

### Round 2
...

### Summary
- **Total issues**: N
- **Fixed**: X
- **Skipped**: Y
- **Rounds**: Z

✓ All critical issues resolved
```

**記録する内容**:
- 各指摘の内容と Severity
- 意思決定 (Fixed / Skipped)
- 理由 (なぜ修正/スキップしたか)

### Step 9: コミットをプッシュ

Decision Log 追記後、全てのコミットをプッシュ:

```bash
git push
```

## オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--max-rounds` | 3 | 最大ループ回数 |
| `--min-severity` | low | 修正対象の最小 Severity |
| `--auto` | false | 全指摘を自動承認 |

## 出力例

```
=== Codex Review & Fix ===

Round 1:
  Review: 3 issues found (1 HIGH, 2 MEDIUM)

  === 指摘 1/3 ===
  File: src/app.zig:42
  Issue: Memory leak
  Severity: HIGH
  修正方針: errdefer を追加
  → [Y] 適用

  === 指摘 2/3 ===
  File: src/ui.zig:15
  Issue: Unused variable
  Severity: LOW
  修正方針: 削除
  → [N] スキップ (理由: 将来使用予定)

  === 指摘 3/3 ===
  ...

  Fixed: 2/3, Skipped: 1/3
  Committed: fix: address codex review feedback (round 1)

Round 2:
  Review: 0 issues found

✓ All issues resolved in 2 rounds

Decision Log posted to PR #42
Pushed to origin/feat/speckit-verifiers
```

## 関連

- `/codex` - 単発レビュー
- `codex-fixer` Agent - 修正実行
- `/pr` - PR 作成
