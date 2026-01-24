# Implementation Plan: Phase 1 - Tree View & Preview

**Branch**: `001-tree-view` | **Date**: 2026-01-22 | **Status**: Complete

## Summary

TUI file explorer with Vim keybindings using libvaxis. Core tree navigation with expand/collapse and file preview.

## Technical Context

**Language/Version**: Zig 0.14.0
**Primary Dependencies**: libvaxis (TUI framework)
**Storage**: N/A (read-only file system access)
**Testing**: Zig built-in test framework
**Target Platform**: Linux/macOS terminals (Ghostty primary)
**Project Type**: Single CLI application
**Performance Goals**: Handle 1000+ files, responsive UI
**Constraints**: No external runtime dependencies

## Constitution Check

- [x] Zig + libvaxis (per constitution)
- [x] Vim keybindings (j/k/h/l)
- [x] No file modification (read-only MVP)
- [x] Ghostty primary target

## Project Structure

### Documentation

```text
specs/001-tree-view/
├── spec.md       # Feature specification
├── plan.md       # This file
└── tasks.md      # Task list
```

### Source Code

```text
src/
├── main.zig      # Entry point, CLI args
├── app.zig       # App state, event loop, key handling
├── tree.zig      # FileTree data structure
└── ui.zig        # Rendering with libvaxis
```

## Architecture

### Model-View-Update Pattern

```
Event → App.handleKey() → State Update → UI.render()
```

### State Machine

```
TreeView ←→ Preview
    ↓
  Quit
```

### Key Data Structures

**FileTree**: Root container with ArrayList of FileEntry
**FileEntry**: name, path, kind, is_hidden, expanded, children, depth
**App**: file_tree, mode, cursor, scroll_offset, show_hidden

### Memory Strategy

- GeneralPurposeAllocator for FileEntry allocation
- Each FileEntry owns its name/path strings
- Recursive deinit on tree cleanup

## Implementation Phases

### Phase 1.1: Project Setup
- build.zig with libvaxis dependency
- Basic main.zig structure

### Phase 1.2: FileTree Data Structure
- FileEntry struct with expand/collapse
- Directory reading with std.fs

### Phase 1.3: Basic TUI
- libvaxis initialization
- Event loop setup
- Tree rendering

### Phase 1.4: Navigation
- j/k cursor movement
- h/l expand/collapse
- Scroll following cursor

### Phase 1.5: File Preview
- Preview mode toggle (o key)
- Text file content display
- Split view layout

### Phase 1.6: Polish
- Hidden file toggle (.)
- CLI path argument
- Status bar with hints
