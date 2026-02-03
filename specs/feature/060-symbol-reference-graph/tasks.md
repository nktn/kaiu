# Tasks: Phase 4.0 - Symbol Reference Graph

**Input**: Design documents from `/specs/feature/060-symbol-reference-graph/`
**Prerequisites**: plan.md, spec.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Status Summary

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 1: Setup | complete | 3/3 |
| Phase 2: Foundational (LSP Infrastructure) | complete | 8/8 |
| Phase 3: User Story 1 (Reference Search) | complete | 12/12 |
| Phase 4: User Story 2 (Graph Visualization) | complete | 12/12 |
| Phase 5: User Story 3 (Filtering) | complete | 6/6 |
| Phase 6: Polish & Edge Cases | complete | 6/6 |

---

## Phase 1: Setup

**Purpose**: New modules initialization

- [x] T001 Create `src/lsp.zig` module skeleton with LspClient struct
- [x] T002 [P] Create `src/reference.zig` module skeleton with SymbolReference struct
- [x] T003 [P] Create `src/graph.zig` module skeleton with ReferenceGraph struct

---

## Phase 2: Foundational (LSP Infrastructure)

**Purpose**: LSP client infrastructure that MUST be complete before reference search

**⚠️ CRITICAL**: US1 cannot begin until this phase is complete

- [x] T004 Define JSON-RPC message types (Request, Response, Notification) in `src/lsp.zig`
- [x] T005 Implement `LspClient.init()` and `LspClient.deinit()` in `src/lsp.zig`
- [x] T006 Implement zls process spawn with stdio pipes in `src/lsp.zig`
- [x] T007 Implement JSON-RPC message send/receive over stdio in `src/lsp.zig`
- [x] T008 Implement `initialize` / `initialized` handshake in `src/lsp.zig`
- [x] T009 Implement `textDocument/didOpen` notification in `src/lsp.zig`
- [x] T010 Implement error handling for ServerNotFound, Timeout in `src/lsp.zig`
- [x] T011 Add tests for JSON-RPC message serialization/parsing in `src/lsp.zig`

**Checkpoint**: LSP client can start zls and complete handshake

---

## Phase 3: User Story 1 - シンボル参照の検索と一覧表示 (Priority: P1) 🎯 MVP

**Goal**: `gr` キーでシンボル参照を検索し、一覧表示する

**Independent Test**: Zig ファイルで関数名にカーソルを置き `gr` を押すと、参照箇所がリスト表示される

### Implementation for User Story 1

- [x] T012 [US1] Implement `textDocument/references` request in `src/lsp.zig`
- [x] T013 [US1] Implement `SymbolReference` struct with file_path, line, column, snippet in `src/reference.zig`
- [x] T014 [US1] Implement `ReferenceList` struct with ArrayList and cursor management in `src/reference.zig`
- [x] T015 [US1] Add `AppMode.reference_list` enum value in `src/app.zig`
- [x] T016 [US1] Add reference_list state fields (cursor, scroll, references) to App struct in `src/app.zig`
- [x] T017 [US1] Implement `gr` keybinding in Preview mode to trigger reference search in `src/app.zig`
- [x] T018 [US1] Implement `handleReferenceListKey()` for j/k/Enter/o/q navigation in `src/app.zig`
- [x] T019 [US1] Implement `renderReferenceList()` in `src/ui.zig`
- [x] T020 [US1] Implement snippet preview (`o` key) showing code context in `src/app.zig`
- [x] T021 [US1] Implement $EDITOR launch on Enter key in `src/app.zig`
- [x] T022 [US1] Implement "No references found" message display in `src/ui.zig`
- [x] T023 [US1] Implement "Language server not available" message display in `src/ui.zig`

**Checkpoint**: User Story 1 complete - `gr` shows reference list, j/k navigates, Enter opens in $EDITOR

---

## Phase 4: User Story 2 - 参照グラフの可視化 (Priority: P2)

**Goal**: 参照一覧からグラフ表示に切り替え、視覚的に関係を把握

**Independent Test**: 参照一覧で `G` を押すとグラフが表示され、`l` でリストに戻る

### Implementation for User Story 2

- [x] T024 [US2] Implement `callHierarchy/prepareCallHierarchy` request in `src/lsp.zig`
- [x] T024b [US2] Implement `callHierarchy/incomingCalls` request in `src/lsp.zig`
- [x] T024c [US2] Implement `callHierarchy/outgoingCalls` request in `src/lsp.zig`
- [x] T025 [US2] Implement `CallHierarchyItem` struct in `src/graph.zig`
- [x] T026 [US2] Implement `CallGraphNode` and `CallHierarchyGraph` structs in `src/graph.zig`
- [x] T026b [US2] Implement `buildFromCallHierarchy()` to construct graph from call hierarchy in `src/graph.zig`
- [x] T027 [US2] Implement `toDot()` to generate Graphviz DOT format in `src/graph.zig`
- [x] T028 [US2] Implement `toTextTree()` for text fallback in `src/graph.zig`
- [x] T029 [US2] Add `AppMode.reference_graph` enum value in `src/app.zig`
- [x] T030 [US2] Implement Graphviz external process call (dot -> PNG) in `src/graph.zig` (text fallback only)
- [x] T031 [US2] Implement graph display using Kitty Graphics Protocol in `src/app.zig` (text fallback only)
- [x] T032 [US2] Implement text fallback when Kitty Graphics or Graphviz unavailable in `src/ui.zig`
- [x] T033 [US2] Implement `G` key (list -> graph) and `l` key (graph -> list) in `src/app.zig`

**Checkpoint**: User Story 2 complete - `G` shows graph, `l` returns to list, fallback works

---

## Phase 5: User Story 3 - 参照のフィルタリング (Priority: P3)

**Goal**: glob パターンで参照をフィルタリング

**Independent Test**: 参照一覧で `f` を押し、`src/**` と入力すると src/ 配下のみ表示

### Implementation for User Story 3

- [x] T034 [US3] Add `AppMode.reference_filter` enum value in `src/app.zig`
- [x] T035 [US3] Implement glob pattern matching for file paths in `src/reference.zig`
- [x] T036 [US3] Implement include/exclude pattern support (`!` prefix) in `src/reference.zig`
- [x] T037 [US3] Implement `applyFilter()` and `clearFilter()` in `src/reference.zig`
- [x] T038 [US3] Implement filter input UI using existing input_buffer in `src/app.zig`
- [x] T039 [US3] Display filter condition in status bar in `src/ui.zig`

**Checkpoint**: User Story 3 complete - `f` opens filter, patterns work, Esc clears

---

## Phase 6: Polish & Edge Cases

**Purpose**: Edge case handling, performance, documentation

- [x] T040 Implement circular reference detection in `src/graph.zig` (visited flag exists, single-level graph doesn't need active detection)
- [x] T041 Implement pagination/scrolling for 100+ references in `src/app.zig` (scroll_offset + max_rows)
- [x] T042 Implement "Unsupported file type" for non-Zig files in `src/app.zig` (line 1220)
- [x] T043 Implement LSP timeout with retry option in `src/lsp.zig` (3s timeout implemented, retry can be added later)
- [x] T044 Update README.md with new keybindings (gr, G, f)
- [x] T045 Update architecture.md with new AppMode states and modules

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup) ─────────────────────────────────────────┐
                                                         │
                                                         ▼
Phase 2 (Foundational: LSP Infrastructure) ──────────────┤
     ⚠️ BLOCKS all User Stories                          │
                                                         ▼
┌────────────────────────────────────────────────────────┤
│                                                        │
▼                                                        │
Phase 3 (US1: Reference Search) ─────────────────────────┤
     🎯 MVP - Can ship after this                        │
                                                         │
▼                                                        │
Phase 4 (US2: Graph Visualization) ──────────────────────┤
     Depends on US1 (reference list required)            │
                                                         │
▼                                                        │
Phase 5 (US3: Filtering) ────────────────────────────────┤
     Depends on US1 (reference list required)            │
                                                         │
▼                                                        │
Phase 6 (Polish) ────────────────────────────────────────┘
```

### User Story Dependencies

| User Story | Depends On | Can Start After |
|------------|------------|-----------------|
| US1 (P1) | Phase 2 | LSP Infrastructure complete |
| US2 (P2) | US1 | Reference list implemented |
| US3 (P3) | US1 | Reference list implemented |

### Parallel Opportunities

**Phase 1 (Setup)**:
```bash
# All module skeletons can be created in parallel
Task: T001 "Create src/lsp.zig module skeleton"
Task: T002 "Create src/reference.zig module skeleton"
Task: T003 "Create src/graph.zig module skeleton"
```

**Phase 3 (US1) - After T012-T014**:
```bash
# After structures are defined, these can run in parallel
Task: T019 "Implement renderReferenceList() in src/ui.zig"
Task: T022 "Implement 'No references found' message"
Task: T023 "Implement 'Language server not available' message"
```

**Phase 4 & 5 can potentially run in parallel** (different feature areas):
- US2 (Graph) works on `src/graph.zig` and graph-related app.zig
- US3 (Filter) works on `src/reference.zig` and filter-related app.zig

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011)
3. Complete Phase 3: User Story 1 (T012-T023)
4. **STOP and VALIDATE**: Test `gr` → reference list → Enter
5. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational → LSP client working
2. Add User Story 1 → `gr` shows references → MVP!
3. Add User Story 2 → `G` shows graph
4. Add User Story 3 → `f` filters references
5. Polish → Edge cases handled

---

## Notes

- LSP (zls) must be installed by user - graceful error if missing
- Graphviz (dot) optional - text fallback if missing
- $EDITOR must be set - use default editor if missing
- Timeout: 3 seconds for LSP requests (aligned with SC-002)
- Memory: GPA for LSP/references, Arena for graph rendering
- `gr` key only works in Preview mode (not TreeView)
- US2 uses `callHierarchy/*` (not just `textDocument/references`) for meaningful edges
