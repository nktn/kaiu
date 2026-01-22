---
name: speckit
description: >
  Specification-driven development workflow. Feature specs → Plan → Tasks → Implementation.
  サブコマンド: specify, clarify, plan, tasks, implement, analyze, constitution, taskstoissues, checklist
---

# Speckit - Specification Workflow

仕様駆動開発のワークフロー管理。

## Subcommands

| Command | Description | File |
|---------|-------------|------|
| `/speckit.specify` | Create feature spec | @specify.md |
| `/speckit.clarify` | Clarify requirements | @clarify.md |
| `/speckit.plan` | Generate implementation plan | @plan.md |
| `/speckit.tasks` | Generate tasks.md | @tasks.md |
| `/speckit.implement` | Execute implementation | @implement.md |
| `/speckit.analyze` | Cross-artifact analysis | @analyze.md |
| `/speckit.constitution` | Project principles | @constitution.md |
| `/speckit.taskstoissues` | Convert to GitHub issues | @taskstoissues.md |
| `/speckit.checklist` | Generate custom checklist | @checklist.md |

## Workflow

```
/speckit.specify    # 仕様作成
       ↓
/speckit.clarify    # 要件明確化 (optional)
       ↓
/speckit.plan       # 実装計画
       ↓
/speckit.tasks      # タスク分解
       ↓
/implement          # Zig統合実装
```

## Key Files

- `.specify/memory/constitution.md` - Project principles
- `.specify/specs/` - Feature specifications
- `.specify/tasks/` - Generated tasks

## Usage

```
/speckit.specify Add fuzzy file search feature
/speckit.clarify
/speckit.plan
/speckit.tasks
/implement
```
