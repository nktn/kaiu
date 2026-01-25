---
name: zig-module-extraction-strategy
description: Strategy for extracting modules from large Zig files while preserving cohesion
---

# Zig Module Extraction Strategy

**Extracted:** 2026-01-25
**Context:** Large Zig files (1000+ lines) with mixed responsibilities

## Problem

A single .zig file grows too large (e.g., 2253 lines), making it harder to navigate and maintain. However, naive splitting by size can reduce cohesion and create unnecessary dependencies.

**Key Challenges**:
1. Deciding WHAT to extract (not just WHERE)
2. Preserving module cohesion (related code stays together)
3. Avoiding excessive cross-module dependencies
4. Maintaining testability

## Solution

### Phase 1: Extract Pure Functions First

Extract functions with **no App state dependencies** into standalone modules.

**Criteria for extraction**:
- ✅ No App state dependencies (may depend on environment like HOME)
- ✅ Self-contained logic (file system operations, encoding, validation)
- ✅ Easily testable in isolation
- ✅ Reusable from multiple call sites

**Example from kaiu refactoring**:

```zig
// BEFORE: app.zig (2253 lines) - everything in one file

pub const App = struct {
    // ... app state ...

    // Mixed: state-dependent and state-independent functions
    fn yankFiles(self: *Self) !void { ... }
    fn isValidFilename(name: []const u8) bool { ... } // ← Pure!
    fn copyDirRecursive(src: []const u8, dest: []const u8) !void { ... } // ← Pure!
    fn formatDisplayPath(allocator: Allocator, path: []const u8) ![]const u8 { ... } // ← Pure!
};
```

**AFTER: Extract App-independent functions**

```zig
// file_ops.zig (390 lines) - App-independent file operations
pub fn isValidFilename(name: []const u8) bool { ... }
pub fn copyDirRecursive(src: []const u8, dest: []const u8) !void { ... }
pub fn formatDisplayPath(allocator: Allocator, path: []const u8) ![]const u8 { ... }
pub fn encodeBase64(allocator: Allocator, data: []const u8) ![]const u8 { ... }
pub fn isBinaryContent(content: []const u8) bool { ... }

// app.zig (1887 lines) - App state and orchestration
const file_ops = @import("file_ops.zig");

pub const App = struct {
    // ... app state ...

    fn yankFiles(self: *Self) !void {
        // Calls file_ops.copyDirRecursive()
        for (paths) |path| {
            try file_ops.copyPath(path, dest);
        }
    }
};
```

### Phase 2: Evaluate State-Heavy Features

For features that depend heavily on App state (e.g., search, preview), evaluate **cost vs benefit**.

**Criteria for NOT extracting**:
- ❌ Accesses multiple app state fields (mode, cursor, scroll, search_matches)
- ❌ State transitions tightly coupled to event loop
- ❌ Extraction would require passing 5+ parameters or a large context struct
- ❌ Code is highly cohesive where it is

**Example: Why search stayed in app.zig**

```zig
// Hypothetical extraction (BAD - too many dependencies)
const search = @import("search.zig");

pub const SearchContext = struct {
    mode: *AppMode,
    cursor: *usize,
    scroll_offset: *usize,
    input_buffer: *ArrayList(u8),
    search_matches: *ArrayList(usize),
    current_match: *usize,
    file_tree: *FileTree,
    show_hidden: bool,
    status_message: *?[]const u8,
    // ... 10+ fields needed
};

// Not worth it - better to keep in App
```

**Decision**: Keep search/preview in app.zig for cohesion.

### Extraction Checklist

Use this checklist before extracting:

#### Extract if:
- [ ] Function has no `self: *Self` parameter (or can be refactored to remove it)
- [ ] Logic is reusable across multiple modules
- [ ] Function can be tested in isolation
- [ ] Less than 3 function parameters needed
- [ ] No complex state synchronization required

#### Keep in app.zig if:
- [ ] Function needs access to 5+ app state fields
- [ ] State transitions are tightly coupled
- [ ] Extraction requires creating a "god struct" context
- [ ] Code is already cohesive where it is

### File Size After Extraction

**Target ranges**:
- 300-600 lines: Optimal (easy to navigate)
- 600-1000 lines: Acceptable (if cohesive)
- 1000-1500 lines: Large but OK (if state-heavy, like app.zig)
- 1500+ lines: Consider extraction

**Actual result** (kaiu):
- app.zig: 2253 → 1887 lines (-366 lines)
- file_ops.zig: 390 lines (new, App-independent functions)
- **Outcome**: Improved without sacrificing cohesion

## When to Use

**Use this pattern when**:
- File exceeds 1000 lines
- Multiple unrelated responsibilities exist
- Pure functions can be identified
- Testing would benefit from isolation

**Skip this pattern if**:
- File is large but highly cohesive
- Extraction creates more problems than it solves
- You're just chasing arbitrary line count targets

## Benefits

1. **Testability**: Pure functions easy to unit test
2. **Reusability**: Utilities can be imported elsewhere
3. **Clarity**: Smaller, focused modules
4. **Maintainability**: Related code stays together

## Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: "God Struct" Context Passing

```zig
// BAD: Context struct just to avoid app.zig
pub const SearchContext = struct {
    mode: *AppMode,
    cursor: *usize,
    // ... 15 more pointers to app fields
};
```

**Why it's bad**: Just recreates the problem elsewhere.

### ❌ Anti-Pattern 2: Splitting by Arbitrary Size

```zig
// BAD: "app.zig is 2000 lines, split into app1.zig and app2.zig"
// app1.zig - first 1000 lines
// app2.zig - next 1000 lines
```

**Why it's bad**: No regard for cohesion or responsibility boundaries.

### ❌ Anti-Pattern 3: Over-Engineering Small Functions

```zig
// BAD: Creating a module for 2 tiny helper functions
// utils.zig
pub fn isEven(x: usize) bool { return x % 2 == 0; }
pub fn isOdd(x: usize) bool { return x % 2 != 0; }
```

**Why it's bad**: Overhead of module import doesn't justify splitting.

## Real-World Example: kaiu Refactoring

**Before**: app.zig (2253 lines)
- App state management
- Event loop
- File operations (copy, delete, clipboard)
- Search logic
- Preview logic
- Path utilities

**After**:
- app.zig (1887 lines): State + event loop + search + preview
- file_ops.zig (390 lines): Pure file operations + utilities

**Not extracted**: Search and preview (too state-dependent)

**Decision rationale**:
```
file_ops.zig: ✅ Pure, testable, reusable
search in app.zig: ✅ Cohesive with state machine
preview in app.zig: ✅ Cohesive with state machine
```

## Related Patterns

- Pure function extraction (functional programming)
- Single Responsibility Principle (but not dogmatically)
- Cohesion over coupling minimization

## Further Reading

- `.claude/rules/architecture.md` - File Size Guidelines
- `.claude/rules/architecture.md` - Design Decision: file_ops.zig モジュール抽出
