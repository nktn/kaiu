# Feature Specification: Phase 2 - File Operations & Utilities

**Feature Branch**: `phase2-file-operations`
**Created**: 2026-01-22
**Status**: Implemented (US1-6 complete)
**Input**: File operations (mark, copy, cut, paste, delete, rename, create), clipboard, search, navigation jumps, help overlay

## Target Persona

**Tanaka-san (仮)**
- Phase 1 で基本操作に慣れた
- ファイル操作もターミナル内で完結したい
- 複数ファイルの一括操作がしたい
- ranger/lf のような操作感を求めている

---

## User Scenarios & Testing

### User Story 1 - File Marking & Bulk Operations (Priority: P1)

Tanaka-san は複数のファイルを別のディレクトリに移動したい。一つずつ操作するのは面倒なので、まとめて選択して一括で移動したい。

**Why this priority**: ファイル操作の基本。マークなしでは一括操作ができない。

**Independent Test**: Space でマーク、y でコピー、移動先で p でペースト。

**Acceptance Scenarios**:

1. **Given** cursor is on a file, **When** user presses `Space`, **Then** file is marked with visual indicator
2. **Given** file is marked, **When** user presses `Space`, **Then** mark is removed
3. **Given** multiple files are marked, **When** user presses `y`, **Then** all marked files are yanked
4. **Given** files are yanked, **When** user navigates to another directory and presses `p`, **Then** files are copied to current directory
5. **Given** files are cut with `d`, **When** user presses `p`, **Then** files are moved (original deleted)

---

### User Story 2 - Delete with Confirmation (Priority: P1)

Tanaka-san は不要なファイルを削除したい。誤削除を防ぐため、確認ダイアログが欲しい。

**Why this priority**: 破壊的操作なので確認が必須。

**Independent Test**: D で削除、確認ダイアログで y/n。

**Acceptance Scenarios**:

1. **Given** cursor is on a file, **When** user presses `D`, **Then** confirmation dialog appears "Delete <filename>? [y/n]"
2. **Given** confirmation dialog is shown, **When** user presses `y`, **Then** file is deleted and dialog closes
3. **Given** confirmation dialog is shown, **When** user presses `n` or `Esc`, **Then** operation is cancelled
4. **Given** multiple files are marked, **When** user presses `D`, **Then** dialog shows "Delete N files? [y/n]"
5. **Given** delete fails (permission error), **When** operation completes, **Then** error message is shown

---

### User Story 3 - Rename & Create (Priority: P2)

Tanaka-san はファイル名を変更したい。また、新しいファイルやディレクトリを作成したい。

**Why this priority**: よく使う操作だが、マーク/コピー/削除より優先度は低い。

**Independent Test**: r でリネーム入力、a/A で新規作成。

**Acceptance Scenarios**:

1. **Given** cursor is on a file, **When** user presses `r`, **Then** rename input appears with current filename
2. **Given** rename input is shown, **When** user edits and presses `Enter`, **Then** file is renamed
3. **Given** rename input is shown, **When** user presses `Esc`, **Then** rename is cancelled
4. **Given** user presses `a`, **When** input appears, **Then** user can type new filename and create file
5. **Given** user presses `A`, **When** input appears, **Then** user can type new directory name and create it

---

### User Story 4 - Search (Priority: P2)

Tanaka-san は大きなプロジェクトでファイルを探したい。ファイル名で検索してすぐにジャンプしたい。

**Why this priority**: ナビゲーション効率化。

**Independent Test**: / で検索モード、入力でフィルタ、n/N でマッチ間移動。

**Acceptance Scenarios**:

1. **Given** tree view is displayed, **When** user presses `/`, **Then** search input appears at bottom
2. **Given** search input is active, **When** user types query, **Then** matching files are highlighted
3. **Given** search has matches, **When** user presses `Enter`, **Then** cursor jumps to first match
4. **Given** search is active, **When** user presses `n`, **Then** cursor moves to next match
5. **Given** search is active, **When** user presses `N`, **Then** cursor moves to previous match
6. **Given** search input is active, **When** user presses `Esc`, **Then** search is cancelled

---

### User Story 5 - Jump Navigation (Priority: P3)

Tanaka-san は長いファイルリストの先頭や末尾にすぐ移動したい。

**Why this priority**: 便利だが必須ではない。

**Independent Test**: gg で先頭、G で末尾。

**Acceptance Scenarios**:

1. **Given** cursor is anywhere in tree, **When** user presses `gg`, **Then** cursor jumps to first item
2. **Given** cursor is anywhere in tree, **When** user presses `G`, **Then** cursor jumps to last item

---

### User Story 6 - Clipboard & Help (Priority: P3)

Tanaka-san はファイルパスをコピーして他のツールで使いたい。また、キーバインドを忘れたときにヘルプを見たい。

**Why this priority**: ユーティリティ機能。

**Independent Test**: c/C でクリップボード、? でヘルプ。

**Acceptance Scenarios**:

1. **Given** cursor is on a file, **When** user presses `c`, **Then** full path is copied to clipboard
2. **Given** cursor is on a file, **When** user presses `C`, **Then** filename only is copied to clipboard
3. **Given** copy succeeds, **When** operation completes, **Then** status message shows "Copied: <path>"
4. **Given** user presses `?`, **When** help overlay appears, **Then** all keybindings are displayed
5. **Given** help overlay is shown, **When** user presses any key, **Then** overlay closes

---

### Edge Cases

- Paste with no yanked files: Show "Nothing to paste"
- Delete empty directory: Should work
- Delete non-empty directory: Confirm and delete recursively
- Rename to existing filename: Show error
- Create file/dir with invalid name: Show error
- Search with no matches: Show "No matches"
- gg/G in empty directory: No-op
- Clipboard not available: Show error message

---

## Requirements

### Functional Requirements

#### File Marking
- **FR-001**: `Space` MUST toggle mark on current file
- **FR-002**: Marked files MUST show visual indicator (e.g., `*` or highlight)
- **FR-003**: Multiple files CAN be marked simultaneously

#### Yank/Cut/Paste
- **FR-004**: `y` MUST yank (copy) marked files, or current file if none marked
- **FR-005**: `d` MUST cut marked files, or current file if none marked
- **FR-006**: `p` MUST paste yanked/cut files to current directory
- **FR-007**: Cut files MUST be deleted from source after successful paste
- **FR-008**: Paste MUST handle filename conflicts (append number or ask)

#### Delete
- **FR-009**: `D` MUST show confirmation dialog before deleting
- **FR-010**: Confirmation MUST show filename(s) being deleted
- **FR-011**: `y` confirms, `n` or `Esc` cancels deletion
- **FR-012**: Directories MUST be deleted recursively

#### Rename/Create
- **FR-013**: `r` MUST open inline rename input with current filename
- **FR-014**: `a` MUST open input for new file creation
- **FR-015**: `A` MUST open input for new directory creation
- **FR-016**: `Enter` confirms, `Esc` cancels input

#### Clipboard
- **FR-017**: `c` MUST copy full path to system clipboard
- **FR-018**: `C` MUST copy filename only to system clipboard
- **FR-019**: Clipboard operation MUST show feedback message

#### Search
- **FR-020**: `/` MUST enter search mode with input at bottom
- **FR-021**: Search MUST highlight matching text with inverted colors (reverse video)
- **FR-022**: `Enter` MUST exit search mode and jump to first match
- **FR-023**: `n` MUST jump to next match
- **FR-024**: `N` MUST jump to previous match
- **FR-025**: `Esc` MUST cancel search mode

#### Navigation
- **FR-026**: `gg` MUST jump to first item in tree
- **FR-027**: `G` MUST jump to last item in tree

#### Help
- **FR-028**: `?` MUST show help overlay with all keybindings
- **FR-029**: Any key MUST dismiss help overlay

#### Status Bar
- **FR-030**: Status bar MUST display absolute path (not `.` or relative path)
- **FR-031**: Paths under home directory MUST be displayed with `~` prefix (e.g., `~/Documents/github/kaiu`)

### Key Entities

- **MarkedFiles**: Set of marked file paths
- **Clipboard**: Yanked/cut files with operation type (copy/cut)
- **SearchState**: Current search query and match indices

---

## Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `Space` | tree | Toggle mark on file |
| `y` | tree | Yank (copy) marked/current |
| `d` | tree | Cut marked/current |
| `p` | tree | Paste |
| `D` | tree | Delete with confirmation |
| `r` | tree | Rename |
| `a` | tree | New file |
| `A` | tree | New directory |
| `c` | tree | Copy full path to clipboard |
| `C` | tree | Copy filename to clipboard |
| `/` | tree | Enter search mode |
| `n` | tree | Next search match |
| `N` | tree | Previous search match |
| `gg` | tree | Jump to first item |
| `G` | tree | Jump to last item |
| `?` | tree | Show help overlay |
| `y` | confirm | Confirm action |
| `n` | confirm | Cancel action |
| `Esc` | confirm/search/input | Cancel |
| `Enter` | search/input | Confirm |

---

## UI Layout

### Tree View with Marked Files
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                                     │
├─────────────────────────────────────────────────────────────┤
│ 📁 myapp/                                                   │
│   📁 src/                                                   │
│ *   📄 main.zig                                             │
│ *   📄 utils.zig                                            │
│   📁 tests/                                                 │
│ > 📄 README.md                                              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ 2 marked  |  y:yank d:cut p:paste D:delete                  │
└─────────────────────────────────────────────────────────────┘
```

### Delete Confirmation Dialog
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                                     │
├─────────────────────────────────────────────────────────────┤
│ 📁 myapp/                                                   │
│   ...                                                       │
│                                                             │
│  ┌─────────────────────────────────────┐                    │
│  │  Delete 2 files?                    │                    │
│  │  - main.zig                         │                    │
│  │  - utils.zig                        │                    │
│  │                                     │                    │
│  │  [y] Yes    [n] No                  │                    │
│  └─────────────────────────────────────┘                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Search Mode
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                                     │
├─────────────────────────────────────────────────────────────┤
│ 📁 myapp/                                                   │
│   📁 src/                                                   │
│ >   📄 [main].zig                                           │
│     📄 utils.zig                                            │
│   📁 tests/                                                 │
│     📄 test_[main].zig                                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ /main█                                         [1/2 matches]│
└─────────────────────────────────────────────────────────────┘

Note: [main] represents inverted/reverse video text highlighting
```

### Help Overlay
```
┌─────────────────────────────────────────────────────────────┐
│                        kaiu Help                            │
├─────────────────────────────────────────────────────────────┤
│  Navigation              File Operations                    │
│  ──────────              ───────────────                    │
│  j/k     Move down/up    Space  Mark/unmark                 │
│  h/l     Back/Open       y      Yank (copy)                 │
│  gg/G    Top/Bottom      d      Cut                         │
│  /       Search          p      Paste                       │
│  n/N     Next/Prev       D      Delete                      │
│                          r      Rename                      │
│  View                    a/A    New file/dir                │
│  ──────                                                     │
│  o       Preview         Clipboard                          │
│  .       Hidden files    ─────────                          │
│  ?       This help       c/C    Copy path/name              │
│  q       Quit                                               │
│                                                             │
│                    Press any key to close                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: User can mark and move 10 files in under 30 seconds
- **SC-002**: User can delete files with confirmation in 2 keypresses (D + y)
- **SC-003**: User can find file by name in under 5 seconds using search
- **SC-004**: All file operations complete without data loss
- **SC-005**: No crashes on permission errors or edge cases

---

## Out of Scope (Future Phases)

- Fuzzy search (Phase 3)
- File preview in search results (Phase 3)
- Redo for file operations (Phase 3)
- Multi-level undo history (Phase 3)
- Trash/recycle bin (Phase 3)
- Bulk rename with pattern (Phase 3)
