# Phase 2: Vim Motions & Navigation

## Overview

Phase 2 enhances navigation with Vim motions, path navigation, search, and utility features. Users who completed Phase 1 can now navigate much faster.

---

## Story 3: Vim Motions & Enhanced Navigation

> Tanaka-san is comfortable with basic j/k navigation. Now they want to move faster - jump to top/bottom, collapse everything at once, and jump directly to a specific path. They also want to search for files by name.

### Acceptance Criteria

#### Jump Commands
- [ ] `gg` jumps to first item
- [ ] `G` jumps to last item
- [ ] `H` collapses all directories
- [ ] `L` expands all directories
- [ ] `Tab` toggles expand/collapse on current directory

#### Path Navigation
- [ ] `gn` opens path input mode
- [ ] Path input supports `~` (home directory)
- [ ] Path input supports `..` (parent directory)
- [ ] `Enter` confirms and navigates to path
- [ ] `Esc` cancels path input
- [ ] Invalid path shows error message

#### Search
- [ ] `/` enters search mode
- [ ] Typing filters tree incrementally
- [ ] `Enter` confirms search and exits search mode
- [ ] `Esc` clears search and returns to normal mode
- [ ] `n` moves to next match
- [ ] `N` moves to previous match
- [ ] Matches are highlighted

#### View
- [ ] `.` toggles hidden files (dotfiles)
- [ ] `R` reloads the tree

#### Clipboard
- [ ] `c` copies full path to clipboard
- [ ] `C` copies filename only to clipboard
- [ ] Shows feedback message "Copied: <path>"

#### Help
- [ ] `?` shows help overlay with all keybindings
- [ ] Any key dismisses help overlay

---

## Keybindings (Phase 2)

### Navigation
| Key | Action |
|-----|--------|
| `gg` | Jump to top |
| `G` | Jump to bottom |
| `Tab` | Toggle expand/collapse |
| `H` | Collapse all |
| `L` | Expand all |

### Directory Navigation
| Key | Action |
|-----|--------|
| `gn` | Go to path (input mode) |

### Search
| Key | Action |
|-----|--------|
| `/` | Enter search mode |
| `n` | Next search match |
| `N` | Previous search match |
| `Esc` | Clear search / cancel |

### View
| Key | Action |
|-----|--------|
| `.` | Toggle hidden files |
| `R` / `F5` | Reload tree |

### Clipboard
| Key | Action |
|-----|--------|
| `c` | Copy full path to clipboard |
| `C` | Copy filename to clipboard |

### Help
| Key | Action |
|-----|--------|
| `?` | Show help |

---

## UI: Search Mode
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                              [?help]│
├─────────────────────────┬───────────────────────────────────┤
│ 📁 myapp/               │                                   │
│   📁 src/               │                                   │
│     📄 main.zig    [*]  │                                   │
│     📄 utils.zig        │                                   │
│   📁 tests/             │                                   │
│ > 📄 README.md          │                                   │
│                         │                                   │
├─────────────────────────┴───────────────────────────────────┤
│ /main█                                         [2 matches]  │
└─────────────────────────────────────────────────────────────┘
```

## UI: Path Input Mode
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                              [?help]│
├─────────────────────────┬───────────────────────────────────┤
│ 📁 myapp/               │                                   │
│   📁 src/               │                                   │
│     📄 main.zig         │                                   │
│                         │                                   │
├─────────────────────────┴───────────────────────────────────┤
│ Go to: ~/projects/other█                                    │
└─────────────────────────────────────────────────────────────┘
```

## UI: Help Overlay
```
┌─────────────────────────────────────────────────────────────┐
│                        kaiu Help                            │
├─────────────────────────────────────────────────────────────┤
│  Navigation                    Search                       │
│  ──────────                    ──────                       │
│  j/k     Move down/up          /       Search               │
│  h/l     Collapse/Expand       n/N     Next/Prev match      │
│  gg/G    Jump top/bottom                                    │
│  H/L     Collapse/Expand all   View                         │
│  Tab     Toggle expand         ──────                       │
│  gn      Go to path            .       Toggle hidden        │
│                                R/F5    Reload               │
│  Clipboard                                                  │
│  ──────────                    Other                        │
│  c       Copy path             ──────                       │
│  C       Copy filename         ?       This help            │
│                                q       Quit                 │
│                                                             │
│                    Press any key to close                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Multi-Key Command Handling

`gg` and `gn` require detecting consecutive keypresses:

1. First `g` → enter "pending" state, show `g-` in status bar
2. Second key within timeout (500ms):
   - `g` → execute `gg` (jump to top)
   - `n` → execute `gn` (go to path)
3. Timeout or other key → cancel pending state

---

## Edge Cases

- `gg` / `G` in empty directory → no-op
- `H` when all collapsed → no-op
- `L` in deep tree → may be slow, show loading indicator
- `gn` with invalid path → show error, stay in input mode
- `gn` with file path → navigate to parent, select file
- Search with no matches → show "No matches"
- `n` / `N` with no search → no-op
- `c` / `C` on directory → copy directory path/name
- Clipboard not available → show error message

---

## Out of Scope (Future Phases)

- Fuzzy search (Phase 3)
- Marks (Phase 3)
- File operations - yank/cut/paste/delete/rename (Phase 3)
- Mouse support (Phase 4)
- VCS integration (Phase 4)
- Preview mode enhancements (Phase 4)