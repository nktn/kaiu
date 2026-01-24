# kaiu Constitution

## Project Identity

**kaiu** is a TUI file explorer written in Zig.

- Name origin: "kai you" → 回遊 (Japanese: migration, wandering)
- Concept: Navigate through file trees like fish swimming through the ocean

## Non-Negotiable Principles

### 1. Target User
- Developers transitioning from VSCode to terminal-based development
- Users who started using Claude Code and want a familiar file explorer experience
- Beginners who want to learn Vim keybindings through practical use

### 2. Technology Stack
- **Language**: Zig (latest stable version)
- **TUI Library**: libvaxis
- **Target Terminal**: Ghostty (primary), but should work on any modern terminal
- **Image Protocol**: Kitty Graphics Protocol for image preview

### 3. Design Principles
- **Familiarity**: Feel like VSCode's file explorer, but in terminal
- **Vim-native**: All navigation uses Vim keybindings (j/k/h/l, gg/G, etc.)
- **Progressive disclosure**: Start simple, reveal power features as user learns
- **No configuration required**: Sensible defaults, zero setup to start

### 4. Core Features (MVP)
- Tree view with expand/collapse
- File preview (text files)
- Basic Vim navigation (j/k for up/down, Enter to expand/open)

### 5. Quality Standards
- No runtime crashes - graceful error handling
- Responsive UI - never block on file operations
- Memory efficient - handle large directories without issues

### 6. What kaiu is NOT
- Not a complicated file manager (no directory moves, no file content editing)
- Not an IDE
- Not a replacement for proper file management tools

## Development Workflow

### Track Selection

開発作業は2つの Track に分かれる:

| Track | コマンド | 用途 | GitHub Label |
|-------|---------|------|--------------|
| **Feature Track** | `/speckit.specify` | ユーザー価値を提供する機能 | `feature` |
| **Technical Track** | `/technical` | 開発者価値、リファクタリング、ドキュメント改善 | `technical` |

**判断基準**: 「この変更でユーザーが新しいことをできるようになるか？」

- **Yes** → Feature Track (`/speckit.specify`)
  - 例: fuzzy search、trash bin、新しいキーバインド
  - spec.md → plan.md → tasks.md のフローを使用

- **No** → Technical Track (`/technical`)
  - 例: app.zig 分割、ドキュメント整理、パフォーマンス改善
  - Issue ベースで直接実装
