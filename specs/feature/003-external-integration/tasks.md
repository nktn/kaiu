# Tasks: Phase 3 - External Integration & VCS Support

**Input**: Design documents from `/specs/feature/003-external-integration/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Status**: In Progress (Phase 1-6 Complete: 50/70 tasks)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create new module files and basic structure

- [x] T001 [P] Create `src/vcs.zig` module with VCSType, VCSMode, VCSFileStatus enums
- [x] T002 [P] Create `src/image.zig` module with ImageFormat, ImageDimensions structs
- [x] T003 [P] Create `src/watcher.zig` module with WatchEvent enum and Watcher struct placeholder
- [x] T004 Add new modules to `build.zig` imports (N/A - Zig auto-resolves imports)

---

## Phase 2: Foundational

**Purpose**: Core infrastructure that user stories depend on

**⚠️ CRITICAL**: Setup module imports before proceeding

- [x] T005 Add VCS state fields to App struct in `src/app.zig` (vcs_type, vcs_mode, vcs_branch, vcs_status)
- [ ] T006 Add file watching state fields to App struct in `src/app.zig` (watching_enabled, watcher, pending_refresh, last_change_time)
- [ ] T007 Add image preview state fields to App struct in `src/app.zig` (preview_is_image, preview_image_dims)
- [ ] T008 Add drop state fields to App struct in `src/app.zig` (drop_pending, drop_target_dir)
- [x] T009 Add `confirm_overwrite` to AppMode enum in `src/app.zig`
- [x] T010 Initialize new state fields in App.init() in `src/app.zig`
- [x] T011 Cleanup new state fields in App.deinit() in `src/app.zig`

**Checkpoint**: State structure ready - user story implementation can begin

---

## Phase 3: User Story 1 - VCS Status Display (Priority: P1) 🎯 MVP

**Goal**: Display Git/JJ file status with colors and branch info in status bar

**Independent Test**: Run kaiu in a Git repo, verify files show colors based on status and branch name appears in status bar

### Implementation for User Story 1

- [x] T012 [US1] Implement detectVCS(path) function in `src/vcs.zig` - check for .git/.jj directories
- [x] T013 [US1] Implement executeCommand() helper in `src/vcs.zig` using std.process.Child
- [x] T014 [US1] Implement getGitStatus() in `src/vcs.zig` - execute `git status --porcelain=v1 -z` and parse output
- [x] T015 [US1] Implement getGitBranch() in `src/vcs.zig` - execute `git branch --show-current`
- [x] T016 [US1] Implement getJJStatus() in `src/vcs.zig` - execute `jj status --color=never` and parse output
- [x] T017 [US1] Implement getJJInfo() in `src/vcs.zig` - execute `jj log` for change ID and bookmark
- [x] T018 [US1] Add `gv` multi-key handler in `src/app.zig` - cycle VCS mode (Auto → JJ → Git → Auto)
- [x] T019 [US1] Implement refreshVCSStatus() in `src/app.zig` - call vcs.zig functions and populate vcs_status
- [x] T020 [US1] Call refreshVCSStatus() on app startup in `src/app.zig` init()
- [x] T021 [US1] Call refreshVCSStatus() in reloadTree() in `src/app.zig`
- [x] T022 [US1] Update renderEntry() in `src/ui.zig` - apply VCS status colors (green/yellow/red/cyan/magenta)
- [x] T023 [US1] Update renderStatusBar() in `src/ui.zig` - display branch name `[main]` or JJ info `@abc123 (main)`
- [x] T024 [US1] Handle VCS errors gracefully in `src/vcs.zig` - return empty status on failure
- [ ] T024a [US1] Add 2-second timeout for VCS commands in `src/vcs.zig` - prevent UI freeze on slow repos
- [x] T025 [US1] Add status message for VCS mode change in `src/app.zig`

**Checkpoint**: VCS status display fully functional - files show colors, branch in status bar, gv cycles modes

---

## Phase 4: User Story 2 - Image Preview (Priority: P1)

**Goal**: Preview PNG, JPG, GIF, WebP images in preview pane with fallback for unsupported terminals

**Independent Test**: Select a PNG file and press `o`, verify image displays or fallback message appears

**Note**: Can run in parallel with US1 (different files, independent functionality)

### Implementation for User Story 2

- [x] T026 [P] [US2] Implement detectImageFormat() in `src/image.zig` - check file extension and magic bytes
- [x] T027 [P] [US2] Implement getImageDimensions() in `src/image.zig` - read PNG IHDR, JPG SOF0, GIF LSD, WebP VP8
- [x] T028 [US2] Research libvaxis image API in `src/image.zig` - check vaxis.graphics for Kitty/Sixel support
- [x] T029 [US2] Implement detectGraphicsProtocol() in `src/image.zig` - vaxis handles via caps.kitty_graphics
- [x] T030 [US2] Update openPreview() in `src/app.zig` - detect image files using image.zig
- [x] T031 [US2] Set preview_is_image and preview_image_dims in `src/app.zig` when opening image preview
- [x] T032 [US2] Implement renderImagePreview() in `src/app.zig` - display image using Kitty Graphics Protocol
- [x] T033 [US2] Implement renderImageFallback() in `src/app.zig` - show `[Image: filename (WxH, size)]` text
- [x] T034 [US2] Update preview title bar in `src/app.zig` - show filename and dimensions
- [x] T035 [US2] Handle corrupted images in `src/image.zig` - return error that triggers fallback display
- [x] T036 [US2] Handle large images (>10MB) in `src/app.zig` - show size warning instead of loading

**Checkpoint**: Image preview functional - images display or show fallback, dimensions shown in title

---

## Phase 5: User Story 3 - Drag & Drop File Import (Priority: P2)

**Goal**: Accept file drops from Finder/external apps and copy to cursor-relative directory

**Independent Test**: Drop a file from Finder onto kaiu window, verify it copies to correct directory

### Implementation for User Story 3

- [x] T037 [US3] Research libvaxis drag & drop support - **BLOCKED**: vaxis doesn't expose terminal drop events
- [ ] T038 [US3] Add DropEvent handling to event loop in `src/app.zig` - parse drop payloads
- [ ] T039 [US3] Implement getDropTargetDir() in `src/app.zig` - cursor on dir → that dir, cursor on file → parent
- [ ] T040 [US3] Implement copyFile() helper in `src/app.zig` - copy single file using std.fs
- [ ] T041 [US3] Implement copyDirectory() helper in `src/app.zig` - recursive directory copy
- [ ] T042 [US3] Implement handleDrop() in `src/app.zig` - process single or multiple dropped files
- [ ] T043 [US3] Implement checkFilenameConflict() in `src/app.zig` - detect existing files with same name
- [ ] T044 [US3] Add confirm_overwrite mode handling in `src/app.zig` - overwrite/rename/cancel options
- [ ] T044a [US3] Implement rename with `name (2).ext` format in `src/app.zig` - space + parenthesis + number
- [ ] T044b [US3] Implement drop queuing in `src/app.zig` - queue drops during other file operations
- [ ] T045 [US3] Implement renderConfirmOverwrite() in `src/ui.zig` - display conflict resolution dialog
- [ ] T046 [US3] Call reloadTree() after successful drop in `src/app.zig`
- [ ] T047 [US3] Add status message for drop result in `src/app.zig` - "Copied N files" or error
- [ ] T048 [US3] Handle unsupported terminals gracefully in `src/app.zig` - silently ignore drops

**Checkpoint**: Drag & drop functional - files copy to correct location, conflicts handled with dialog

---

## Phase 6: User Story 4 - File System Watching (Priority: P3)

**Goal**: Auto-refresh tree on external file changes with debouncing and VCS integration

**Independent Test**: Create file in another terminal, verify kaiu tree updates within 2 seconds

**Dependencies**: Partial dependency on US1 (VCS refresh integration)

### Implementation for User Story 4

- [x] T049 [US4] Implement macOS file watching in `src/watcher.zig` - using mtime polling for cross-platform
- [x] T050 [US4] Implement Linux file watching in `src/watcher.zig` - using mtime polling for cross-platform
- [x] T051 [US4] Implement Watcher.init() in `src/watcher.zig` - create watcher for directory
- [x] T052 [US4] Implement Watcher.deinit() in `src/watcher.zig` - cleanup resources
- [x] T053 [US4] Implement Watcher.poll() in `src/watcher.zig` - non-blocking check for events
- [x] T054 [US4] Integrate watcher polling into event loop in `src/app.zig`
- [x] T055 [US4] Implement debouncing logic in `src/app.zig` - 300ms window, coalesce events
- [x] T056 [US4] Add `W` key handler in `src/app.zig` - toggle watching_enabled
- [x] T057 [US4] Update renderStatusBar() in `src/app.zig` - display `[W]` icon when watching enabled
- [x] T058 [US4] Call refreshVCSStatus() on watched file change in `src/app.zig` (integrates with US1)
- [x] T059 [US4] Preserve cursor position on auto-refresh in `src/app.zig` - store/restore current path
- [x] T060 [US4] Verify expanded_paths preservation on auto-refresh in `src/app.zig`
- [x] T061 [US4] Add status message for watching toggle in `src/app.zig` - "Watching enabled/disabled"

**Checkpoint**: File watching functional - external changes auto-refresh tree, VCS status updates, icon shows state

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, documentation, edge cases

- [ ] T062 [P] Add error handling for all VCS command failures in `src/vcs.zig`
- [ ] T063 [P] Add error handling for image loading failures in `src/image.zig`
- [ ] T064 [P] Add error handling for watcher initialization failures in `src/watcher.zig`
- [x] T065 Update help overlay in `src/ui.zig` - add gv, W keys
- [ ] T066 Update README.md - add new keybindings (gv, W)
- [ ] T067 Update README.md - add new features (VCS status, image preview, drag & drop, file watching)
- [ ] T068 Memory leak check - verify all allocations freed in deinit()
- [ ] T069 Performance test - verify VCS status adds no perceptible delay
- [ ] T070 Performance test - verify file watching CPU usage under 5%

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies - start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 - BLOCKS all user stories
- **Phase 3 (US1 - VCS)**: Depends on Phase 2 - Can start immediately after
- **Phase 4 (US2 - Image)**: Depends on Phase 2 - Can run PARALLEL with US1
- **Phase 5 (US3 - Drop)**: Depends on Phase 2 - Can run PARALLEL with US1/US2
- **Phase 6 (US4 - Watching)**: Depends on Phase 2 + US1 partial (VCS integration)
- **Phase 7 (Polish)**: Depends on all user stories complete

### User Story Dependencies

```
Phase 1: Setup
    ↓
Phase 2: Foundational (BLOCKS all)
    ↓
    ├── US1: VCS Status (P1) ──────────────┐
    │                                       │
    ├── US2: Image Preview (P1) [parallel] │
    │                                       │
    ├── US3: Drag & Drop (P2) [parallel]   │
    │                                       ↓
    └────────────────────────────────► US4: File Watching (P3)
                                            │
                                            ↓
                                      Phase 7: Polish
```

### Parallel Opportunities

Within each phase, tasks marked [P] can run in parallel:

**Phase 1**: T001, T002, T003 (all parallel - different files)
**Phase 4 (US2)**: T026, T027 (parallel - different functions in same file)
**Phase 7**: T062, T063, T064 (parallel - different files)

**Cross-Story Parallelism**:
- US1, US2, US3 can all start after Phase 2 completes
- Only US4 has dependency on US1 (for VCS refresh integration)

---

## Parallel Example: After Phase 2 Completes

```bash
# Can launch these user stories in parallel (different developers or agents):

# Developer/Agent A: US1 - VCS Status
Task: "T012 [US1] Implement detectVCS(path) in src/vcs.zig"
Task: "T013 [US1] Implement executeCommand() helper in src/vcs.zig"
...

# Developer/Agent B: US2 - Image Preview
Task: "T026 [P] [US2] Implement detectImageFormat() in src/image.zig"
Task: "T027 [P] [US2] Implement getImageDimensions() in src/image.zig"
...

# Developer/Agent C: US3 - Drag & Drop
Task: "T037 [US3] Research libvaxis drag & drop support"
...
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T011)
3. Complete Phase 3: US1 - VCS Status (T012-T025)
4. **STOP and VALIDATE**: Test VCS colors and branch display
5. This alone provides significant value for developers

### Incremental Delivery

| Increment | User Stories | Value Delivered |
|-----------|--------------|-----------------|
| MVP | US1 | VCS status colors, branch in status bar |
| +Image | US1 + US2 | Also preview images in kaiu |
| +Watch | US1 + US2 + US4 | Auto-refresh on file changes |
| Full | All | Complete external integration |

### Recommended Order

1. **US1 (VCS)** - Most valuable for developer workflow
2. **US2 (Image)** - Parallel with US1 if capacity allows
3. **US4 (Watching)** - Builds on US1, high UX value
4. **US3 (Drop)** - Nice to have, may be blocked by terminal support

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- US3 (Drag & Drop) depends on terminal/libvaxis support - research first
- US4 (Watching) depends on US1 for VCS refresh integration
- All stories should be independently testable after completion
- Commit after each task or logical group
