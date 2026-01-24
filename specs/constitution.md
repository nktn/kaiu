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
