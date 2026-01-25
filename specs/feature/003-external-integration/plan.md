# Implementation Plan: Phase 3 - External Integration & VCS Support

## Technical Context

- **Zig version**: 0.15.2 (minimum)
- **TUI library**: libvaxis (vaxis-0.5.1)
- **Target terminal**: Ghostty (primary), modern terminals with Kitty/Sixel support
- **Current modules**:
  - `src/main.zig` - Entry point, CLI args, path validation (~140 lines)
  - `src/app.zig` - App state, event loop, state machine (~1100 lines)
  - `src/tree.zig` - FileTree data structure (~370 lines)
  - `src/ui.zig` - libvaxis rendering, highlighting (~420 lines)

## Constitution Check

Verify the plan aligns with specs/constitution.md principles:

- [x] **Target User alignment**: VSCode to terminal users (Tanaka-san persona)
  - VCS status display mirrors VSCode's built-in Git integration
  - Image preview reduces Finder dependency
  - Drag & drop bridges GUI and TUI workflows
  - File watching matches VSCode's auto-refresh behavior

- [x] **Design Principles**:
  - **Familiarity**: VCS colors match common conventions (green=new, yellow=modified, red=deleted)
  - **Vim-native**: New keybindings follow Vim patterns (`gv` for VCS mode toggle)
  - **Progressive disclosure**: VCS info appears automatically in repos, hidden elsewhere
  - **Zero config**: Auto-detect VCS type, default watching enabled

- [x] **Quality Standards**:
  - **No crashes**: Graceful fallback for unsupported terminals, corrupted images, VCS errors
  - **Responsive UI**: Debounced file watching, async VCS status fetch
  - **Memory efficient**: Status caching, image size limits

- [x] **What kaiu is NOT**:
  - No Git staging/commit/push operations (out of scope)
  - No image editing (out of scope)
  - No video/audio preview (out of scope)

## Architecture Decisions

### New Modules

```
src/
├── main.zig          # Entry point (existing)
├── app.zig           # App state, event loop (existing, ~1100 lines)
├── tree.zig          # FileTree data structure (existing)
├── ui.zig            # Rendering (existing)
├── vcs.zig           # NEW: VCS detection, status fetching
├── watcher.zig       # NEW: File system watching
└── image.zig         # NEW: Image format detection, loading
```

**Rationale**:
- `vcs.zig`: Encapsulates Git/JJ command execution and status parsing
- `watcher.zig`: Isolates OS-specific file watching logic
- `image.zig`: Handles image format detection and metadata extraction

### State Changes

#### New AppMode Values

No new AppMode values needed. Existing modes suffice:
- VCS mode cycling is a setting toggle, not a mode
- Image preview uses existing `preview` mode
- Drop confirmation uses existing `confirm_delete` pattern (repurpose or add `confirm_overwrite`)

**Update**: Add one new mode for drop conflict resolution:

```zig
pub const AppMode = enum {
    tree_view,
    preview,
    search,
    path_input,
    rename,
    new_file,
    new_dir,
    confirm_delete,
    confirm_overwrite,  // NEW: for drop filename conflict
    help,
};
```

#### New State Fields in App Struct

```zig
pub const App = struct {
    // ... existing fields ...

    // VCS State (US1)
    vcs_type: VCSType,           // Auto, Git, JJ, None
    vcs_mode: VCSMode,           // User-selected mode (Auto/Git/JJ)
    vcs_branch: ?[]const u8,     // Branch name or change ID
    vcs_status: std.StringHashMap(VCSFileStatus), // path -> status

    // File Watching State (US4)
    watching_enabled: bool,      // Toggle with 'W' key
    watcher: ?*Watcher,          // OS file watcher handle
    pending_refresh: bool,       // Debounce flag
    last_change_time: i64,       // For debouncing

    // Image Preview State (US2)
    preview_is_image: bool,      // true if current preview is image
    preview_image_dims: ?ImageDimensions, // width x height

    // Drop State (US3)
    drop_pending: ?DropEvent,    // Files waiting to be processed
    drop_target_dir: ?[]const u8, // Target directory for drop

    // ... existing fields ...
};
```

#### New Enums and Structs

```zig
// vcs.zig
pub const VCSType = enum {
    none,   // Not in a repository
    git,    // Git repository
    jj,     // Jujutsu repository
};

pub const VCSMode = enum {
    auto,   // Auto-detect (JJ preferred if both exist)
    git,    // Force Git
    jj,     // Force JJ
};

pub const VCSFileStatus = enum {
    unchanged,
    modified,    // Yellow
    untracked,   // Green
    deleted,     // Red (staged or unstaged)
    renamed,     // Cyan
    conflict,    // Magenta
    // Note: Ignored files are NOT tracked - VCS output only, no .gitignore parsing
};

// image.zig
pub const ImageDimensions = struct {
    width: u32,
    height: u32,
};

pub const ImageFormat = enum {
    png,
    jpg,
    gif,
    webp,
    unknown,
};

// watcher.zig
pub const WatchEvent = enum {
    created,
    deleted,
    modified,
    renamed,
};

// app.zig (for drops)
pub const DropEvent = struct {
    paths: [][]const u8,
    timestamp: i64,
};
```

### Memory Strategy

| Module | Allocator | Rationale |
|--------|-----------|-----------|
| VCS status cache | StringHashMap with owned keys | Status persists until next refresh |
| VCS branch name | Owned string, freed on refresh | Changes infrequently |
| Watcher | GPA | Long-lived, freed on deinit |
| Image metadata | ArenaAllocator (render_arena) | Temporary, per-frame |
| Drop paths | ArrayList with owned copies | Freed after processing |

### External Process Integration

#### Git Command Execution

```zig
// vcs.zig
pub fn getGitStatus(allocator: Allocator, repo_path: []const u8) !StatusResult {
    // Use std.process.Child to run:
    // git -C <repo_path> status --porcelain=v1 -z
    // Parse output: XY path\0
}

pub fn getGitBranch(allocator: Allocator, repo_path: []const u8) ![]const u8 {
    // git -C <repo_path> branch --show-current
}
```

#### JJ Command Execution

```zig
pub fn getJJStatus(allocator: Allocator, repo_path: []const u8) !StatusResult {
    // jj --no-pager -R <repo_path> status --color=never
    // Parse output differently from Git
}

pub fn getJJInfo(allocator: Allocator, repo_path: []const u8) !JJInfo {
    // jj --no-pager -R <repo_path> log -r @ --no-graph -T 'change_id ++ " " ++ bookmarks'
}
```

#### Async Considerations

**Decision**: Use synchronous execution with debouncing and timeout.

**Rationale**:
- Git/JJ status is fast for most repos (< 100ms)
- Debouncing (300ms) already handles rapid changes
- Async would add complexity without significant UX benefit
- If performance becomes an issue, can add background thread later

**Implementation**:
- Execute VCS commands synchronously on:
  - App startup
  - Manual reload (`R`)
  - Debounced file change detection
- **Timeout**: 2 second timeout for VCS commands to prevent UI freeze
  - On timeout: show no VCS status, display warning in status message
  - User can still navigate and use other features
- **Fallback**: If VCS command fails or times out, display files without status colors

## Implementation Phases

### Phase 1: VCS Status Display (P1) - US1

**Dependencies**: None (can start immediately)

**Tasks**:

1. **Task 1.1**: Create `src/vcs.zig` module
   - VCSType, VCSMode, VCSFileStatus enums
   - detectVCS(path) function
   - Basic module structure

2. **Task 1.2**: Implement Git status parsing
   - Execute `git status --porcelain=v1 -z`
   - Parse output to VCSFileStatus map
   - Handle errors gracefully

3. **Task 1.3**: Implement Git branch detection
   - Execute `git branch --show-current`
   - Handle detached HEAD state

4. **Task 1.4**: Implement JJ status parsing
   - Execute `jj status --color=never`
   - Parse output to VCSFileStatus map
   - Handle errors gracefully

5. **Task 1.5**: Implement JJ info detection
   - Execute `jj log` for change ID and bookmark
   - Format as `@change-id (bookmark)`

6. **Task 1.6**: Add VCS state to App struct
   - New fields: vcs_type, vcs_mode, vcs_branch, vcs_status
   - Initialize in App.init()
   - Cleanup in App.deinit()

7. **Task 1.7**: Implement VCS mode cycling (`gv`)
   - Add `gv` key handler (multi-key command)
   - Cycle: Auto -> JJ -> Git -> Auto
   - Refresh status on mode change

8. **Task 1.8**: Update ui.zig for VCS colors
   - Modify renderEntry() to apply VCS status colors
   - Color mapping per FR-003

9. **Task 1.9**: Update status bar for VCS info
   - Display branch name: `[main]` for Git
   - Display change ID: `@abc123 (main)` for JJ
   - Show nothing for non-repo directories

10. **Task 1.10**: Integrate VCS refresh with tree reload
    - Call VCS status refresh in reloadTree()
    - Handle VCS not found gracefully

### Phase 2: Image Preview (P1) - US2

**Dependencies**: Phase 1 not required (parallel possible)

**Tasks**:

1. **Task 2.1**: Create `src/image.zig` module
   - ImageFormat enum
   - ImageDimensions struct
   - detectImageFormat(path) function

2. **Task 2.2**: Implement image format detection
   - Check file extension (.png, .jpg, .jpeg, .gif, .webp)
   - Validate magic bytes for robustness

3. **Task 2.3**: Implement image metadata extraction
   - Read image dimensions from file headers
   - PNG: IHDR chunk
   - JPG: SOF0 marker
   - GIF: Logical Screen Descriptor
   - WebP: VP8/VP8L chunk

4. **Task 2.4**: Research libvaxis image support
   - Check if vaxis supports Kitty Graphics Protocol
   - Check Sixel support
   - Determine API for image display

5. **Task 2.5**: Implement terminal graphics detection
   - Query terminal capabilities
   - Detect Kitty protocol support
   - Detect Sixel support

6. **Task 2.6**: Implement image preview rendering
   - If Kitty/Sixel supported: render image
   - If not: show text fallback `[Image: filename (WxH)]`
   - Scale large images to fit preview pane

7. **Task 2.7**: Update preview mode for images
   - Add preview_is_image flag
   - Add preview_image_dims
   - Modify openPreview() to detect images

8. **Task 2.8**: Handle image edge cases
   - Corrupted files: show error message
   - Large files (>10MB): show size warning
   - Unsupported formats: show fallback

### Phase 3: Drag & Drop (P2) - US3

**Dependencies**: None (parallel possible, but lower priority)

**Tasks**:

1. **Task 3.1**: Research libvaxis drag & drop support
   - Check if vaxis exposes terminal drag & drop events
   - Identify terminal protocols for file drops

2. **Task 3.2**: Add DropEvent to event union
   - Extend Event union to include drop events
   - Parse drop payloads (file paths)

3. **Task 3.3**: Implement drop target determination
   - Cursor on directory: target = that directory
   - Cursor on file: target = parent directory

4. **Task 3.4**: Implement single file copy
   - Copy dropped file to target directory
   - Handle errors gracefully

5. **Task 3.5**: Implement multi-file drop
   - Process multiple files in sequence
   - Report progress in status bar

6. **Task 3.6**: Implement directory drop (recursive copy)
   - Recursively copy dropped directory
   - Preserve directory structure

7. **Task 3.7**: Implement filename conflict handling
   - Add confirm_overwrite mode
   - Options: overwrite / rename / cancel
   - Rename uses `name (2).ext` format (space + parenthesis + number)
   - UI for conflict resolution

8. **Task 3.8**: Implement drop queuing
   - Queue drops during other file operations (rename, delete, paste)
   - Process queued drops after current operation completes
   - Show "Drop queued" status message

9. **Task 3.9**: Auto-refresh after drop
   - Call reloadTree() on successful drop
   - Preserve cursor position

10. **Task 3.10**: Graceful degradation for unsupported terminals
   - Detect if terminal supports drops
   - Silently ignore drops if not supported

### Phase 4: File System Watching (P3) - US4

**Dependencies**: Phase 1 (VCS status refresh integration - FR-006)

**Tasks**:

1. **Task 4.1**: Create `src/watcher.zig` module
   - Watcher struct
   - WatchEvent enum
   - Platform abstraction

2. **Task 4.2**: Implement macOS file watching (FSEvents)
   - Use FSEvents API for recursive directory watching
   - FSEvents automatically handles subdirectory creation/deletion
   - Simpler than kqueue for tree-wide monitoring

3. **Task 4.3**: Implement Linux file watching (inotify)
   - Use std.posix.inotify
   - Watch for IN_CREATE, IN_DELETE, IN_MODIFY, IN_MOVED_*

4. **Task 4.4**: Add watcher state to App
   - watching_enabled (default: true)
   - watcher handle
   - Debounce state

5. **Task 4.5**: Implement debouncing
   - Collect events for 300ms window
   - Coalesce multiple events on same file
   - Single refresh after debounce

6. **Task 4.6**: Implement `W` key to toggle watching
   - Toggle watching_enabled
   - Show/hide status bar icon

7. **Task 4.7**: Update status bar with watching icon
   - Display `[W]` when watching is enabled (ASCII for terminal compatibility)
   - Hide when disabled

8. **Task 4.8**: Integrate with VCS status refresh
   - When watching detects change, also refresh VCS status
   - Respects vcs_mode setting

9. **Task 4.9**: Preserve cursor position on auto-refresh
   - Store current file path before refresh
   - Find and restore cursor position after refresh

10. **Task 4.10**: Preserve expanded directories on auto-refresh
    - expanded_paths already exists in App
    - Ensure it's used during auto-refresh

11. **Task 4.11**: Performance testing
    - Measure CPU usage with watching enabled
    - Target: < 5% increase

## Dependencies

### External Dependencies

| Dependency | Purpose | Status |
|------------|---------|--------|
| libvaxis | TUI rendering | Used (v0.5.1) |
| Git | VCS status (optional) | System binary |
| JJ | VCS status (optional) | System binary |

### libvaxis Capabilities Research

**Image Support**:
- libvaxis supports Kitty Graphics Protocol via `vaxis.graphics`
- Sixel support may be available
- Need to verify API during Task 2.4

**Drag & Drop**:
- Terminal drag & drop is typically handled via OSC 52 or terminal-specific protocols
- libvaxis may expose this via event loop
- Need to verify during Task 3.1

**File Watching**:
- Not provided by libvaxis (it's a TUI library)
- Must use std library or OS-specific APIs

### Terminal Graphics Protocol Detection

Detection strategy:
1. Check TERM/TERM_PROGRAM environment variables
2. Query terminal using DA1/DA2 sequences
3. Fall back to text if unknown

Known support:
- Ghostty: Kitty Graphics Protocol
- Kitty: Kitty Graphics Protocol
- iTerm2: Sixel, proprietary protocol
- WezTerm: Kitty Graphics Protocol, Sixel
- Others: Text fallback

## Risks & Mitigations

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| libvaxis lacks image support | Major | Medium | Implement text fallback first; image is optional UX enhancement |
| Drag & drop not supported by vaxis | Major | High | Make US3 optional; users can use `cp` command |
| File watching complex on cross-platform | Medium | Medium | Start with macOS (primary target); add Linux later |
| VCS command slow on large repos | Medium | Low | Debounce, consider caching or background refresh |
| Memory leak in VCS status cache | Medium | Low | Clear cache on every refresh; proper deinit |

### Mitigation Details

1. **Image Support Fallback**
   - Always implement text fallback first
   - Image rendering is enhancement, not blocker
   - Test on Ghostty (primary target) first

2. **Drag & Drop Optional**
   - Research vaxis capabilities early (Task 3.1)
   - If not supported, document as "terminal limitation"
   - Users can still use: copy path -> paste in shell -> cp

3. **File Watching Complexity**
   - Phase 4 is P3 (lowest priority)
   - Use FSEvents on macOS for recursive directory watching
   - Manual `R` refresh always works as fallback

4. **VCS Performance**
   - Use `--porcelain` for faster parsing
   - Debounce to avoid rapid calls
   - Cache results until explicit refresh

## Open Questions

1. **libvaxis Image API**: What is the exact API for rendering images? Need to check vaxis source.

2. **Terminal Drop Protocol**: Does vaxis expose OSC 52 or similar for receiving dropped files?

3. ~~**File Watching on macOS**: Use kqueue directly or shell out to `fswatch`?~~ → **Resolved**: Use FSEvents for recursive watching

4. **JJ Output Format**: Is `jj status --color=never` output stable/documented? Consider using `--template` for locale-independent parsing.

## Task Priority Summary

| Phase | User Story | Priority | Est. Tasks | Dependencies |
|-------|------------|----------|------------|--------------|
| 1 | VCS Status (US1) | P1 | 10 | None |
| 2 | Image Preview (US2) | P1 | 8 | None |
| 3 | Drag & Drop (US3) | P2 | 9 | None |
| 4 | File Watching (US4) | P3 | 11 | Phase 1 (partial) |

**Recommended Execution Order**:
1. Phase 1 (VCS) - Most valuable for developer workflow
2. Phase 2 (Image) - Can run in parallel with Phase 1
3. Phase 4 (Watching) - Complements Phase 1
4. Phase 3 (Drop) - Nice to have, may be blocked by terminal support
