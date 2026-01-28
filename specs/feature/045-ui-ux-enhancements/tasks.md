# Tasks: UI/UX Enhancements (Phase 3.5)

**Input**: Design documents from `/specs/feature/045-ui-ux-enhancements/`
**Prerequisites**: plan.md (required), spec.md (required)

**Tests**: TDD approach - write tests first where applicable

**Organization**: Tasks grouped by user story for independent implementation

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Related Issues

- #51: Mouse click cursor movement (US1)
- #52: Double-click expand/preview (US2)
- #55: Status bar file info (US3)
- #53: Nerd Font icons (US4)

---

## Phase 1: Setup

**Purpose**: No setup needed - extending existing codebase

**Status**: N/A (existing project)

---

## Phase 2: Foundational

**Purpose**: No foundational work needed - each user story can be implemented independently

**Note**: US2 depends on US1, but US3 and US4 are fully independent

---

## Phase 3: User Story 1 - Mouse Click Cursor Movement (Priority: P1) 🎯 MVP

**Goal**: Click anywhere in the file tree to move cursor to that row
**Issue**: #51
**Independent Test**: Click a row, verify cursor moves to that row

### Tests for User Story 1

- [x] T001 [US1] Add test for handleLeftClick with valid row in src/app.zig
- [x] T002 [US1] Add test for click outside tree area (status bar) in src/app.zig
- [x] T002a [US1] Add test for click on blank row below last entry in src/app.zig

### Implementation for User Story 1

- [x] T003 [US1] Implement handleLeftClick() function in src/app.zig
- [x] T004 [US1] Add left-click detection in handleMouse() in src/app.zig
- [x] T005 [US1] Calculate visible index from screen row + scroll offset in src/app.zig
- [x] T006 [US1] Exclude status bar area (bottom 2 rows) from click detection in src/app.zig
- [x] T006a [US1] Ignore clicks on blank rows below last entry in src/app.zig

**Checkpoint**: Mouse click moves cursor - US1 complete, ready for manual testing

---

## Phase 4: User Story 2 - Double Click Expand/Preview (Priority: P2)

**Goal**: Double-click to expand directories or open file preview
**Issue**: #52
**Depends on**: US1 (mouse click infrastructure)
**Independent Test**: Double-click directory to expand, double-click file to preview

### Tests for User Story 2

- [x] T007 [US2] Add test for double-click detection (within 400ms) in src/app.zig
- [x] T008 [US2] Add test for single-click (exceeds 400ms) in src/app.zig
- [x] T009 [US2] Add test for clicks on different entries (not double-click) in src/app.zig
- [x] T009a [US2] Add test for scroll between clicks (same row, different entry) in src/app.zig

### Implementation for User Story 2

- [x] T010 [US2] Add last_click_time (Instant) and last_click_entry (visible index) fields to App in src/app.zig
- [x] T011 [US2] Add double_click_threshold_ns constant (400ms) in src/app.zig
- [x] T012 [US2] Implement double-click detection using monotonic time and entry identity in handleLeftClick() in src/app.zig
- [x] T013 [US2] Call expandOrEnter() on double-click in src/app.zig
- [x] T013a [US2] Handle broken symlink double-click with error message in src/app.zig

**Checkpoint**: Double-click works - US2 complete, ready for manual testing

---

## Phase 5: User Story 3 - Status Bar File Info (Priority: P2)

**Goal**: Show file name, size, and modification time in status bar
**Issue**: #55
**Independent Test**: Select a file, verify status bar shows filename | size | modified

### Tests for User Story 3

- [x] T014 [P] [US3] Add test for formatSize() edge cases (0B, 1K, 1M, 1G) in src/ui.zig
- [x] T015 [P] [US3] Add test for formatRelativeTime() (just now, minutes, hours, days) in src/ui.zig
- [x] T015a [P] [US3] Add test for stat failure handling (show "-") in src/ui.zig

### Implementation for User Story 3

- [x] T016 [P] [US3] Implement formatSize() function in src/ui.zig
- [x] T017 [P] [US3] Implement formatRelativeTime() function (English format, 30-day cutoff) in src/ui.zig
- [x] T018 [US3] Add CachedFileInfo struct and cache on cursor change in src/app.zig
- [x] T019 [US3] Update renderStatusBar() to show file info layout in src/ui.zig
- [x] T020 [US3] Handle directory case (show item count instead of size) in src/ui.zig
- [x] T020a [US3] Handle stat failure (show "-" for size/time) in src/ui.zig
- [x] T020b [US3] Handle empty tree (show path only) in src/ui.zig

**Checkpoint**: Status bar shows file info - US3 complete, ready for manual testing

---

## Phase 6: User Story 4 - Nerd Font Icons (Priority: P3)

**Goal**: Display Nerd Font icons for files and directories
**Issue**: #53
**Independent Test**: Start kaiu, verify icons appear for .zig files and directories

### Tests for User Story 4

- [x] T021 [P] [US4] Add test for getIcon() with known extensions in src/icons.zig
- [x] T022 [P] [US4] Add test for getIcon() with special filenames in src/icons.zig
- [x] T023 [P] [US4] Add test for getIcon() fallback to default in src/icons.zig
- [x] T024 [P] [US4] Add test for directory icons (open/closed) in src/icons.zig

### Implementation for User Story 4

- [x] T025 [P] [US4] Create src/icons.zig with Icon struct definition
- [x] T026 [US4] Add extension_icons StaticStringMap (20+ file types) in src/icons.zig
- [x] T027 [US4] Add filename_icons StaticStringMap (special files) in src/icons.zig
- [x] T028 [US4] Implement getIcon() function in src/icons.zig
- [x] T029 [P] [US4] Add --no-icons CLI flag parsing in src/main.zig
- [x] T030 [US4] Add show_icons field to App and pass from main in src/app.zig
- [x] T031 [US4] Update renderEntry() to prepend icon before filename using vaxis stringWidth() in src/ui.zig
- [x] T032 [US4] Add icons module to build.zig

**Checkpoint**: Icons display - US4 complete, ready for manual testing

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and final validation

- [x] T033 [P] Update README.md with new mouse operations and icons flag
- [x] T034 [P] Update architecture.md with new App fields
- [ ] T035 Run manual tests: click, double-click, status bar, icons
- [ ] T036 Run manual tests: --no-icons flag disables icons
- [ ] T037 Verify in Ghostty, Kitty, WezTerm (if available)

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)         → N/A
Phase 2 (Foundational)  → N/A
Phase 3 (US1)           → No dependencies
Phase 4 (US2)           → Depends on US1 completion
Phase 5 (US3)           → No dependencies (can parallel with US1)
Phase 6 (US4)           → No dependencies (can parallel with US1, US3)
Phase 7 (Polish)        → All user stories complete
```

### User Story Dependencies

```
US1 (P1) ──────────────────> US2 (P2)
    │
    │ (independent)
    │
US3 (P2) ←── can start in parallel
US4 (P3) ←── can start in parallel
```

### Parallel Opportunities

Within each story, tasks marked [P] can run in parallel:
- US3: T014, T015 (tests) and T016, T017 (format functions)
- US4: T021-T024 (tests), T025 (icons.zig), T029 (main.zig)

---

## Parallel Example: US3 + US4 (Independent Stories)

```bash
# Can run in parallel after US1 starts:

# US3 - Status Bar (different file: ui.zig)
Task: "Implement formatSize() in src/ui.zig"
Task: "Implement formatRelativeTime() in src/ui.zig"

# US4 - Icons (different file: icons.zig, main.zig)
Task: "Create src/icons.zig with Icon struct"
Task: "Add --no-icons CLI flag in src/main.zig"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete US1 (T001-T006)
2. **STOP and VALIDATE**: Test mouse click independently
3. Demo: "Click to move cursor" feature works

### Incremental Delivery

1. US1 → Mouse click works → Demo
2. US2 → Double-click works (builds on US1) → Demo
3. US3 → Status bar info works → Demo
4. US4 → Icons display → Demo
5. Polish → Documentation complete → Release

### Recommended Order (Single Developer)

1. US1 (P1) - Foundation for US2
2. US3 (P2) - Independent, quick win
3. US2 (P2) - Extends US1
4. US4 (P3) - Largest scope, lowest priority
5. Polish

---

## Notes

- [P] tasks = different files, no dependencies
- US2 MUST wait for US1 (same handleLeftClick function)
- US3 and US4 can start immediately after project setup
- Commit after each task or logical group
- Manual testing after each checkpoint
- Issues will be closed when corresponding US is complete
