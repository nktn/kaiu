# Feature Specification: Phase 3 - External Integration & VCS Support

**Feature Branch**: `003-external-integration`
**Created**: 2026-01-25
**Status**: Draft
**Input**: VSCodeからターミナル開発に移行してきた田中さんが、ブラウザやSlackなど外部アプリと併用しながら快適に開発できるようにする。VCSステータス表示、画像プレビュー、ドラッグ&ドロップ、ファイルシステム監視を実装。

## Clarifications

### Session 2026-01-25

- Q: VCS ステータスはいつ取得・更新されるべきか？ → A: 起動時 + 手動 `R` + ファイルシステム監視連動 (`W` でトグル可能)
- Q: ドロップしたファイルはどこに保存されるか？ → A: B - カーソル位置がディレクトリならそこ、ファイルならその親ディレクトリ
- Q: 監視状態をどのように表示するか？ → A: A - ステータスバーにアイコン表示 (オン時のみ表示)
- Q: Git staged と unstaged を区別するか？ → A: A - 区別しない (両方とも黄色 - シンプルさ優先)
- Q: 起動時のファイルシステム監視はデフォルトでオン/オフ？ → A: B - デフォルトオン (ユーザーが `W` で無効化可能)

---

## Target Persona

**田中さん (Phase 1-2 から継続)**
- Phase 1-2 で kaiu の基本操作に慣れた
- Claude Code と kaiu を併用して開発中
- まだブラウザ、Slack、Finder など GUI アプリと併用している
- VSCode の「当たり前の機能」がターミナルでも欲しい
- 完全なターミナル移行ではなく、GUI と TUI のハイブリッド運用

---

## User Scenarios & Testing

### User Story 1 - VCS Status Display (Priority: P1)

田中さんは Claude Code でコードを生成しながら開発している。kaiu でファイルツリーを見たとき、どのファイルが変更されたか、新規作成されたかが一目で分かると嬉しい。VSCode では当たり前にできていた機能。

**Why this priority**: 開発ワークフローの中核。ファイルの変更状態が分からないと、commit 漏れやレビュー漏れが発生しやすい。

**Independent Test**: kaiu を Git リポジトリで起動し、ファイルの色分けとステータスバーのブランチ名を確認。

**Acceptance Scenarios**:

1. **Given** kaiu is running in a Git repository, **When** a file is modified, **Then** file name is displayed in yellow
2. **Given** kaiu is running in a Git repository, **When** a new untracked file exists, **Then** file name is displayed in green
3. **Given** kaiu is running in a Git repository, **When** a file is staged for deletion, **Then** file name is displayed in red
4. **Given** kaiu is running in a Git repository, **When** a file is renamed, **Then** file name is displayed in cyan
5. **Given** kaiu is running in a Git repository, **When** a file is in .gitignore, **Then** file name is displayed in gray
6. **Given** kaiu is running in a Git repository, **When** user views status bar, **Then** current branch name is displayed (e.g., `[main]`)
7. **Given** kaiu is running in a JJ repository, **When** user views status bar, **Then** change ID and bookmark are displayed (e.g., `@abc123 (main)`)
8. **Given** both .git and .jj directories exist, **When** kaiu starts with Auto mode, **Then** JJ is used by default
9. **Given** kaiu is running in a VCS repository, **When** user presses `gv`, **Then** VCS mode cycles: Auto → JJ → Git → Auto
10. **Given** watching is enabled in VCS repository, **When** file is modified externally, **Then** VCS status color updates automatically
11. **Given** kaiu is running in VCS repository, **When** user presses `R`, **Then** VCS status is refreshed

---

### User Story 2 - Image Preview (Priority: P1)

田中さんは Slack でデザイナーから画像ファイルをもらった。今まではプレビューするために Finder を開いていたが、kaiu 上で確認できれば作業が途切れない。

**Why this priority**: 外部アプリ依存を減らす重要な機能。画像ファイルは開発でよく扱う (アイコン、スクリーンショット、デザインモック)。

**Independent Test**: kaiu で PNG/JPG ファイルを選択し、`o` でプレビュー表示。

**Acceptance Scenarios**:

1. **Given** cursor is on a PNG file, **When** user presses `o`, **Then** image is displayed in preview pane
2. **Given** cursor is on a JPG file, **When** user presses `o`, **Then** image is displayed in preview pane
3. **Given** cursor is on a GIF file, **When** user presses `o`, **Then** image is displayed in preview pane (static frame)
4. **Given** cursor is on a WebP file, **When** user presses `o`, **Then** image is displayed in preview pane
5. **Given** image is larger than preview pane, **When** preview opens, **Then** image is scaled to fit
6. **Given** terminal does not support graphics protocols, **When** user previews image, **Then** fallback message shows "[Image: filename.png (1920x1080)]"
7. **Given** preview is open with image, **When** user presses `o` or `h`, **Then** preview closes and returns to tree view

---

### User Story 3 - Drag & Drop File Import (Priority: P2)

田中さんはブラウザでダウンロードした素材を kaiu のプロジェクトディレクトリに追加したい。Finder からドラッグ&ドロップで入れられれば、ターミナルとGUIの連携がスムーズになる。

**Why this priority**: GUI からの入力経路として重要だが、代替手段 (cp コマンド、Finder での操作) があるため P2。

**Independent Test**: Finder からファイルを kaiu ウィンドウにドロップし、カーソル位置に応じたディレクトリにコピーされることを確認。

**Acceptance Scenarios**:

1. **Given** cursor is on a directory, **When** user drops a file from Finder, **Then** file is copied to that directory
2. **Given** cursor is on a file, **When** user drops a file from Finder, **Then** file is copied to the parent directory
3. **Given** kaiu is running, **When** user drops multiple files, **Then** all files are copied to target directory
4. **Given** kaiu is running, **When** user drops a folder, **Then** folder and contents are copied recursively
5. **Given** file with same name exists, **When** user drops file, **Then** confirmation prompt appears (overwrite/rename/cancel)
6. **Given** drop completes successfully, **When** operation finishes, **Then** file tree is refreshed automatically
7. **Given** terminal does not support drag & drop, **When** user attempts drop, **Then** nothing happens (no error, graceful ignore)

---

### User Story 4 - File System Watching (Priority: P3)

田中さんは Claude Code でファイルを生成している。生成されたファイルが kaiu に自動で表示されれば、手動で `R` を押す必要がなくなる。

**Why this priority**: UX 向上機能だが、手動リロード (`R`) で代替可能。他の機能より優先度を下げる。

**Independent Test**: 別ターミナルでファイルを作成し、kaiu のツリーが自動更新されることを確認。

**Acceptance Scenarios**:

1. **Given** kaiu starts, **When** app is initialized, **Then** file system watching is enabled by default
2. **Given** watching is enabled, **When** file is created externally, **Then** file appears in tree within 2 seconds
3. **Given** watching is enabled, **When** file is deleted externally, **Then** file disappears from tree within 2 seconds
4. **Given** watching is enabled, **When** file is renamed externally, **Then** tree reflects new name within 2 seconds
5. **Given** watching is enabled, **When** multiple files change rapidly, **Then** updates are debounced (no UI flicker)
6. **Given** watching is enabled, **When** user views status bar, **Then** watching icon [👁] is displayed
7. **Given** watching is enabled, **When** user presses `W`, **Then** watching is disabled and icon disappears
8. **Given** watching is disabled, **When** file is created externally, **Then** tree is NOT updated (manual `R` required)
9. **Given** watching is enabled and VCS repository exists, **When** file is modified externally, **Then** VCS status is also updated
10. **Given** watching is active, **When** performance impact is measured, **Then** CPU usage increase is under 5%

---

### Edge Cases

- VCS repository not found: Show no VCS indicator, files in default color
- .gitignore parsing error: Ignore .gitignore, show all files in default color
- Corrupted image file: Show "[Cannot display: corrupted or unsupported format]"
- Very large image (>10MB): Show "[Image too large to preview]"
- Drop during file operation: Queue the drop, process after current operation
- Symlink in tree: Show VCS status of target file
- File changes while preview is open: Refresh preview content
- Network drive or slow filesystem: Increase debounce timeout automatically

---

## Requirements

### Functional Requirements

#### VCS Status Display
- **FR-001**: App MUST detect VCS type by checking for `.jj` and `.git` directories
- **FR-002**: App MUST prioritize JJ over Git when both exist (in Auto mode)
- **FR-003**: App MUST display file status using colors:
  - Green: New/Untracked
  - Yellow: Modified (staged and unstaged are not distinguished)
  - Red: Deleted (staged)
  - Cyan: Renamed
  - Gray: Ignored
  - Magenta: Conflict
- **FR-004**: App MUST display branch/bookmark info in status bar
  - Git format: `[branch-name]`
  - JJ format: `@change-id (bookmark)`
- **FR-005**: `gv` MUST cycle VCS mode: Auto → JJ → Git → Auto
- **FR-006**: App MUST refresh VCS status on:
  - App startup (initial load)
  - Manual tree reload (`R` key)
  - File system change detection (when watching is enabled, integrated with US4)
- **FR-007**: App MUST work without VCS (no color, no status) in non-repository directories
- **FR-026**: App MUST allow toggling file system watching on/off with `W` key (default: on, applies to both tree refresh and VCS status update)
- **FR-027**: App MUST display watching status icon in status bar when watching is enabled (hidden when disabled)

#### Image Preview
- **FR-008**: App MUST support image preview for PNG, JPG, JPEG, GIF, WebP formats
- **FR-009**: App MUST use Kitty Graphics Protocol for image display (primary)
- **FR-010**: App MUST fall back to Sixel if Kitty protocol not supported
- **FR-011**: App MUST show text fallback if no graphics protocol available
- **FR-012**: App MUST scale large images to fit preview pane
- **FR-013**: App MUST handle corrupted/unreadable images gracefully

#### Drag & Drop
- **FR-014**: App MUST accept file drops from external applications
- **FR-015**: App MUST copy dropped files to target directory (cursor on directory → that directory; cursor on file → parent directory)
- **FR-016**: App MUST handle multiple file drops in single operation
- **FR-017**: App MUST prompt on filename conflict (overwrite/rename/cancel)
- **FR-018**: App MUST refresh tree after successful drop
- **FR-019**: App MUST gracefully ignore drops on unsupported terminals

#### File System Watching
- **FR-020**: App MUST detect file creation in watched directories
- **FR-021**: App MUST detect file deletion in watched directories
- **FR-022**: App MUST detect file rename in watched directories
- **FR-023**: App MUST debounce rapid changes (100-500ms window)
- **FR-024**: App MUST preserve cursor position on auto-refresh when possible
- **FR-025**: App MUST preserve expanded directory state on auto-refresh

### Key Entities

- **VCSStatus**: File status (untracked, modified, deleted, renamed, ignored, conflict, unchanged)
- **VCSType**: Repository type (Auto, Git, JJ, None)
- **VCSInfo**: Branch name, change ID, bookmark
- **ImageFormat**: Supported image format (PNG, JPG, GIF, WebP)
- **DropEvent**: Dropped file paths, source application, drop location
- **FileWatcher**: Watched directories, debounce timer, pending changes

---

## Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `gv` | tree | Cycle VCS mode (Auto → JJ → Git → Auto) |
| `W` | tree | Toggle file system watching (affects auto-refresh and VCS update) |
| `o` | tree (on image) | Open image preview |
| `o` | preview (image) | Close preview |

---

## UI Layout

### Tree View with VCS Status
```
┌─────────────────────────────────────────────────────────────┐
│ kaiu - ~/projects/myapp                    [👁] [main]     │
├─────────────────────────────────────────────────────────────┤
│ 📁 myapp/                                                   │
│   📁 src/                                                   │
│     📄 main.zig              (yellow - modified)            │
│     📄 new_module.zig        (green - untracked)            │
│   📁 assets/                                                │
│     📄 logo.png              (gray - ignored)               │
│ > 📄 README.md                                              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ j/k:move  gv:VCS mode  o:preview  q:quit                    │
└─────────────────────────────────────────────────────────────┘
```

### Image Preview
```
┌─────────────────────────────────────────────────────────────┐
│ logo.png (1920x1080)                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    ┌──────────────┐                         │
│                    │              │                         │
│                    │   [IMAGE]    │                         │
│                    │              │                         │
│                    └──────────────┘                         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ o:close  q:quit                                             │
└─────────────────────────────────────────────────────────────┘
```

### Image Preview Fallback (No Graphics Support)
```
┌─────────────────────────────────────────────────────────────┐
│ logo.png                                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│         [Image: logo.png (1920x1080, 245KB)]                │
│                                                             │
│         Graphics protocol not supported.                    │
│         Use a terminal with Kitty or Sixel support.         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ o:close  q:quit                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: User can identify file VCS status at a glance without running `git status`
- **SC-002**: User can preview common image formats (PNG, JPG, GIF) in under 1 second
- **SC-003**: User can import files via drag & drop in under 3 seconds per file
- **SC-004**: External file changes appear in tree within 2 seconds without manual refresh
- **SC-005**: VCS status display adds no perceptible delay to tree rendering
- **SC-006**: No crashes on VCS errors, unsupported terminals, or corrupted files

---

## Related Issues

- #33: Auto-refresh file list on external changes - File system watching (US4)
- #36: Display images in preview pane - Image preview (US2)
- #37: Support drag & drop to copy files - Drag & drop (US3)

---

## Out of Scope (Future Phases)

- Git staging from kaiu (add, commit, push)
- Image editing or manipulation
- Video/audio preview
- Cloud storage integration (Dropbox, Google Drive)
- Network file system specific optimizations
- Animated GIF playback
- Image zoom/pan controls
