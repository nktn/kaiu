# Phase 1: Tree View & Preview

## Overview

Phase 1 delivers the core experience: browsing files in a tree and previewing their contents. This covers Story 1 (Tree View) and Story 2 (Preview).

## Target Persona

**Tanaka-san (仮)**
- Daily VSCode user
- Recently started using Claude Code
- Interested in terminal-based development
- Wants to learn Vim keybindings through practical use
- Misses VSCode's file explorer when working in terminal

---

## Story 1: First Steps - Tree View

> Tanaka-san is working with Claude Code on a project. They think "where was that file again?" and type `tree` but it's too deep to read. Opening VSCode feels like overkill. They want to quickly see the file structure.

### Acceptance Criteria

- [ ] Running `kaiu` or `kaiu .` opens current directory in tree view
- [ ] Running `kaiu <path>` opens specified directory
- [ ] `j` / `k` moves cursor up/down (Vim first experience!)
- [ ] `Enter` expands/collapses directories
- [ ] `q` quits the application
- [ ] Directories show with trailing `/` or folder icon
- [ ] Hidden files (dotfiles) are hidden by default
- [ ] `a` toggles showing hidden files

---

## Story 2: Preview Files

> Tanaka-san found the file in the tree. "What was in this file again?" They want to preview without opening a full editor. Like VSCode's preview on click.

### Acceptance Criteria

- [ ] `Enter` on a file opens preview pane on the right
- [ ] `l` also opens preview (Vim-style: move right into file)
- [ ] `h` closes preview and returns focus to tree (Vim-style: move left)
- [ ] Text files show content with line numbers
- [ ] Large files show first N lines with "[truncated]" indicator
- [ ] Binary files show "[Binary file]" message
- [ ] Preview pane shows filename at top

---

## UI Layout
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                              [?help]│
├─────────────────────────┬───────────────────────────────────┤
│ 📁 myapp/               │ README.md                         │
│   📁 src/               │ ─────────────────────────────────│
│     📄 main.zig         │  1 │ # My App                     │
│     📄 utils.zig        │  2 │                              │
│   📁 tests/             │  3 │ A simple application...      │
│ > 📄 README.md          │  4 │                              │
│   📄 build.zig          │  5 │ ## Installation              │
│                         │  6 │                              │
│                         │  7 │ ```bash                      │
│                         │  8 │ zig build                    │
│                         │  9 │ ```                          │
│                         │                                   │
├─────────────────────────┴───────────────────────────────────┤
│ j/k:move  Enter:open  h/l:navigate  a:hidden  q:quit        │
└─────────────────────────────────────────────────────────────┘
```

## Keybindings (Phase 1)

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `h` | Close preview / collapse directory |
| `l` / `Enter` | Open preview / expand directory |
| `a` | Toggle hidden files |
| `q` | Quit |
| `?` | Show help |

## Out of Scope (Future Phases)

- `gg` / `G` jump commands (Phase 2)
- `/` search (Phase 2)
- Fuzzy search & marks (Phase 3)
- Drag & drop, image preview (Phase 4)