# Feature Specification: Phase 1 - Tree View & Preview

**Feature Branch**: `phase1-tree-view`
**Created**: 2026-01-22
**Status**: Complete
**Input**: TUI file explorer with Vim keybindings - basic tree navigation and file preview

## Target Persona

**Tanaka-san (仮)**
- Daily VSCode user
- Recently started using Claude Code
- Interested in terminal-based development
- Wants to learn Vim keybindings through practical use
- Misses VSCode's file explorer when working in terminal

---

## User Scenarios & Testing

### User Story 1 - Tree View Navigation (Priority: P1)

Tanaka-san is working with Claude Code on a project. They think "where was that file again?" and type `tree` but it's too deep to read. Opening VSCode feels like overkill. They want to quickly see the file structure and navigate with Vim keys.

**Why this priority**: Core functionality - without tree navigation, the app has no value.

**Independent Test**: Launch app, navigate with j/k, expand/collapse directories with l/h.

**Acceptance Scenarios**:

1. **Given** user runs `kaiu` with no arguments, **When** app starts, **Then** current directory tree is displayed
2. **Given** user runs `kaiu ~/projects`, **When** app starts, **Then** ~/projects directory tree is displayed
3. **Given** tree is displayed, **When** user presses `j`, **Then** cursor moves down one item
3. **Given** tree is displayed, **When** user presses `k`, **Then** cursor moves up one item
4. **Given** cursor is on a collapsed directory, **When** user presses `l`, **Then** directory expands to show contents
5. **Given** cursor is on an expanded directory, **When** user presses `h`, **Then** directory collapses
6. **Given** cursor is on a file inside a directory, **When** user presses `h`, **Then** cursor moves to parent directory
7. **Given** app is running, **When** user presses `q`, **Then** app exits cleanly

---

### User Story 2 - File Preview (Priority: P2)

Tanaka-san found the file in the tree. "What was in this file again?" They want to preview without opening a full editor.

**Why this priority**: Preview adds significant value but requires tree navigation to work first.

**Independent Test**: Navigate to a file, press `o` to preview, press `o` again to close.

**Acceptance Scenarios**:

1. **Given** cursor is on a text file, **When** user presses `o`, **Then** full-screen preview shows file content with line numbers
2. **Given** preview is open, **When** user presses `o`, **Then** preview closes and returns to tree view
3. **Given** preview is open, **When** user presses `j`, **Then** preview scrolls down
4. **Given** preview is open, **When** user presses `k`, **Then** preview scrolls up
5. **Given** cursor is on a binary file, **When** user presses `o`, **Then** preview shows "[Binary file - X bytes]"
6. **Given** cursor is on a large file (>100KB), **When** user presses `o`, **Then** preview shows "[File too large]"

---

### User Story 3 - Hidden Files (Priority: P3)

Tanaka-san wants to see dotfiles sometimes, but not always cluttering the view.

**Why this priority**: Nice-to-have, basic navigation works without it.

**Independent Test**: Press `.` to toggle hidden files visibility.

**Acceptance Scenarios**:

1. **Given** tree is displayed with hidden files hidden, **When** user presses `.`, **Then** dotfiles become visible
2. **Given** tree is displayed with hidden files shown, **When** user presses `.`, **Then** dotfiles are hidden

---

### Edge Cases

- Empty directory: Show empty tree, j/k do nothing
- Permission denied on directory: Show error indicator, skip expansion
- Very deep nesting: Handle indentation gracefully
- Single file in directory: Navigation still works
- Root level `h`: No-op (can't go higher)

---

## Requirements

### Functional Requirements

- **FR-001**: `kaiu` (no args) MUST open current directory
- **FR-002**: `kaiu <path>` MUST open specified directory
- **FR-003**: `kaiu ~` MUST expand to home directory
- **FR-004**: App MUST display directory tree with proper indentation
- **FR-005**: App MUST show directories with trailing `/` or folder indicator
- **FR-006**: App MUST support `j`/`k` for cursor movement
- **FR-007**: App MUST support `l` to expand directory
- **FR-008**: App MUST support `h` to collapse directory or move to parent
- **FR-009**: App MUST support `H` to collapse all directories
- **FR-010**: App MUST support `L` to expand all directories
- **FR-011**: App MUST support `o` to toggle file preview
- **FR-012**: App MUST support `.` to toggle hidden files visibility
- **FR-013**: App MUST support `q` to quit
- **FR-014**: Preview MUST display file content in full-screen mode
- **FR-015**: Preview MUST show line numbers
- **FR-016**: Preview MUST detect and handle binary files
- **FR-017**: Preview MUST handle large files gracefully

### Key Entities

- **FileEntry**: Represents a file or directory (name, path, kind, expanded state, hidden flag)
- **FileTree**: Collection of FileEntry items with parent-child relationships
- **AppMode**: Current mode (tree_view, preview)

---

## Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `j` / `↓` | tree | Move cursor down |
| `k` / `↑` | tree | Move cursor up |
| `h` / `←` | tree | Collapse directory or move to parent |
| `l` / `→` | tree | Expand directory |
| `H` | tree | Collapse all directories |
| `L` | tree | Expand all directories |
| `o` | tree | Toggle preview |
| `o` | preview | Close preview |
| `j` | preview | Scroll down |
| `k` | preview | Scroll up |
| `.` | tree | Toggle hidden files |
| `q` | any | Quit |

---

## UI Layout

### Tree View (default)
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                                     │
├─────────────────────────────────────────────────────────────┤
│ 📁 myapp/                                                   │
│   📁 src/                                                   │
│     📄 main.zig                                             │
│     📄 utils.zig                                            │
│   📁 tests/                                                 │
│ > 📄 README.md                                              │
│   📄 build.zig                                              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ j/k:move  l:open  h:back  o:preview  .:hidden  q:quit       │
└─────────────────────────────────────────────────────────────┘
```

### Preview (full-screen)
```
┌─────────────────────────────────────────────────────────────┐
│ README.md                                                   │
├─────────────────────────────────────────────────────────────┤
│  1 │ # My App                                               │
│  2 │                                                        │
│  3 │ A simple application written in Zig.                   │
│  4 │                                                        │
│  5 │ ## Installation                                        │
│  6 │                                                        │
│  7 │ ```bash                                                │
│  8 │ zig build                                              │
│  9 │ ```                                                    │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ j/k:scroll  o:close  q:quit                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: User can navigate a 100+ file project tree in under 10 seconds
- **SC-002**: User can preview any text file with 2 keypresses (navigate + o)
- **SC-003**: App starts and displays tree in under 1 second
- **SC-004**: No crashes on edge cases (empty dirs, permission errors, binary files)

---

## Out of Scope (Future Phases)

- `gg` / `G` jump commands (Phase 2)
- `/` search (Phase 2)
- Help overlay `?` (Phase 2)
- Clipboard operations (Phase 2)
- Fuzzy search & marks (Phase 2)
- File operations - yank/cut/paste/delete/rename (Phase 2)
