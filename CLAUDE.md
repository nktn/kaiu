# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**kaiu** (回遊 - "wandering/migration") is a TUI file explorer written in Zig. It provides VSCode-like file browsing with Vim keybindings for developers transitioning to terminal-based workflows.

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | Zig (latest stable) |
| TUI Library | libvaxis |
| Image Protocol | Kitty Graphics Protocol |
| Target Terminal | Ghostty (primary) |

## Development Commands

```bash
zig build           # Build the project
zig build run       # Build and run
zig build test      # Run all tests
```

## Project Structure

```
kaiu/
├── src/
│   ├── main.zig    # Entry point, CLI argument parsing
│   ├── app.zig     # Application state and main loop
│   ├── tree.zig    # FileTree struct, directory reading
│   └── ui.zig      # libvaxis rendering, layout
├── build.zig       # Build configuration
├── build.zig.zon   # Dependencies (libvaxis)
└── tests/
```

## Architecture

The application follows a Model-View-Update pattern:

- **Model** (`app.zig`): Application state (cursor position, expanded directories, preview state)
- **View** (`ui.zig`): Renders tree and preview panes using libvaxis
- **Update** (`app.zig`): Handles keyboard events, updates state
- **Data** (`tree.zig`): File tree structure with expand/collapse support

### Key Data Structures

- `FileTree`: Recursive tree of directory entries with expand/collapse state
- `AppState`: Current cursor, focused pane, show_hidden flag, preview content

### Vim Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `h` | Close preview / collapse directory |
| `l` / `Enter` | Open preview / expand directory |
| `a` | Toggle hidden files |
| `q` | Quit |

## Design Principles

1. **VSCode-familiar**: Tree view with expand/collapse feels like VSCode's explorer
2. **Vim-native**: Navigation uses j/k/h/l, not arrow keys
3. **Zero config**: Works immediately with sensible defaults
4. **No blocking**: File operations never freeze the UI

## Development Workflow

```
Planning                Implementation              Review & Merge
────────                ──────────────              ──────────────
/speckit.specify
/speckit.clarify
/speckit.plan
/speckit.tasks
      │
      ▼
 /implement ─────────────────────────────┐
      │                                  │
      ├── zig-architect (設計判断)        │
      ├── zig-tdd (各タスク)              │
      ├── zig-build-resolver (エラー時)   │
      │                                  │
      ▼                                  │
   zig-refactor-cleaner (クリーンアップ)  │
      │                                  │
      ▼                                  │
   /learn (パターン保存)                  │
      │                                  │
      ▼                                  │
    /pr (PR作成) ◄───────────────────────┘
      │
      ▼
   /codex (レビュー) ──→ PR コメントに結果追記
      │
      ▼
  修正方針決定 ──→ Decision Log を PR コメントに追記
      │
      ▼
  最終修正
      │
      ▼
   /pr merge
```

### Decision Log ルール

レビュー指摘を採用/スキップする際は、PR コメントに Decision Log を残す:

```markdown
## Decision Log

### [指摘内容] (Severity - 採用/スキップ)

**Issue**: 何が指摘されたか
**Decision**: どうするか
**Rationale**: なぜその判断か
**Alternatives considered**: 他に検討した選択肢
```

**目的**:
- 意思決定の経緯を記録
- 後から「なぜこうなった？」を追跡可能に
- レビュアーとの認識合わせ

### Commands

| Phase | Command | Description |
|-------|---------|-------------|
| Specify | `/speckit.specify` | spec.md 作成 |
| Clarify | `/speckit.clarify` | 要件明確化 |
| Plan | `/speckit.plan` | plan.md, data-model.md |
| Tasks | `/speckit.tasks` | tasks.md 作成 |
| **Implement** | `/implement` | **Zig統合実装 (TDD + build-fix + review + learn)** |

### Key Files

- `.specify/memory/constitution.md` - 原則
- `.specify/specs/` - 仕様
- `.specify/tasks/` - タスク

## Zig Build Engineer Skill

When working with `build.zig`, refer to `.claude/skills/zig-build-engineer/`:

| Reference | Content |
|-----------|---------|
| `SKILL.md` | Quick start, workflow, troubleshooting |
| `references/api-quick-reference.md` | Build, Compile, Run, Module APIs |
| `references/build-system-concepts.md` | DAG model, module system, dependencies |
| `references/common-patterns.md` | 13 template patterns (exe, lib, tests, cross-compile, etc.) |

Key patterns for kaiu:
- Executable + Tests pattern for main build
- Dependencies pattern for libvaxis integration
- Custom Build Options for compile-time config

## Zig Development Agents & Skills

自動で `/implement` から呼ばれる:

| Agent/Skill | Role |
|-------------|------|
| `orchestrator` | タスク依存分析・並行実行制御 |
| `zig-architect` | 設計判断 → architecture.md |
| `zig-tdd` | RED → GREEN → REFACTOR |
| `zig-build-resolver` | ビルドエラー修正 |
| `zig-refactor-cleaner` | 全タスク完了後のクリーンアップ |
| `codex` (skill) | PR 後のコードレビュー |

### Orchestrator の役割

```
tasks.md 読み込み
      │
      ▼
依存関係を分析
      │
      ▼
並行実行可能なタスクを特定
      │
      ├── Task A ──→ zig-tdd
      ├── Task B ──→ zig-tdd  (並行)
      │
      ▼
完了追跡 → 次のタスク
      │
      ▼
全タスク完了 → zig-refactor-cleaner
```

設計判断は **`.claude/rules/architecture.md`** に蓄積される。

## Rules

`.claude/rules/` に開発ルールを配置:

| File | Description |
|------|-------------|
| `architecture.md` | 設計判断ログ、状態遷移図、モジュール構成 |
| `security.md` | Zig セキュリティガイドライン |
| `performance.md` | Zig パフォーマンスガイドライン |
| `agents.md` | Agent 使い分け・実行戦略 |

### Security Guidelines Summary

- **Secret Management**: 環境変数使用、ハードコード禁止
- **Input Validation**: パストラバーサル防止、ファイルパス検証
- **Memory Safety**: defer/errdefer パターン、Use-After-Free 防止
- **TUI Security**: エスケープシーケンスインジェクション対策

### Performance Guidelines Summary

- **Allocator Selection**: Arena (一括解放), FixedBuffer (スタック), GPA (デバッグ)
- **Memory Layout**: SoA vs AoS の適切な選択
- **Allocation Avoidance**: スタック優先、ArrayList 事前確保
- **TUI Performance**: 差分レンダリング、遅延読み込み

## Zig Implementation Commands

`/implement` が統合コマンド。個別コマンドは手動でも使用可能：

| Command | Description | Auto in /implement |
|---------|-------------|:------------------:|
| `/implement` | **統合実装 (推奨)** | - |
| `/tdd` | Red-Green-Refactor | ✓ 各タスク |
| `/build-fix` | ビルドエラー修正 | ✓ エラー時 |
| `/codex` | Codex CLI レビュー | ✓ フェーズ終 |
| `/learn` | パターン保存 | ✓ 完了時 |
| `/pr` | PR作成・status・merge | - |

## What kaiu is NOT

- Not a file manager (no copy/move/delete)
- Not an IDE
- Not a replacement for proper file management tools
