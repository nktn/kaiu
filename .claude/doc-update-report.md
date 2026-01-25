# Doc Update & Learn Report

**Date**: 2026-01-25
**Session**: Issue #41 (app.zig Refactoring)

---

## Documentation Updates

### ✅ architecture.md

**Updated sections**:

1. **Module Structure** - Added file_ops.zig to module list
   ```
   src/
   ├── main.zig      # Entry point, CLI args, path validation (~174 lines)
   ├── app.zig       # App state, event loop, state machine (~1887 lines)
   ├── file_ops.zig  # File operations, path utilities (~390 lines) [NEW]
   ├── tree.zig      # FileTree data structure (~370 lines)
   └── ui.zig        # libvaxis rendering, highlighting (~463 lines)
   ```

2. **Module Responsibilities** - Added file_ops.zig row
   - ファイル・ディレクトリ操作 (copy/delete)
   - パス表示フォーマット
   - バリデーション
   - Base64エンコード (OSC 52用)

3. **File Size Guidelines** - Updated current file sizes
   ```
   - app.zig: ~1887行 (凝集度を保ちつつ、file_ops.zig を抽出済み)
   - file_ops.zig: ~390行 (適正 - App非依存のファイル操作)
   ```

4. **Design Decisions Log** - Added new entry
   ```markdown
   ### [2026-01-25] file_ops.zig モジュール抽出
   **Context**: app.zig が 2253行と肥大化、ファイル操作関連のコードを分離
   **Decision**: file_ops.zig を新規作成し、App非依存のファイルシステム操作を抽出
   **Result**: app.zig: 2253行 → 1887行 (-366行)、file_ops.zig: 390行 (新規)
   ```

### ✅ CLAUDE.md

**Updated section**: Architecture
- Added file_ops.zig to module list with description
- Maintains Model-View-Update pattern explanation

### ✅ README.md

**No changes needed** - Already up to date with file_ops.zig in Project Structure

---

## Pattern Learning

### 📚 New Patterns Saved

#### 1. `zig-module-extraction-strategy.md`

**What it teaches**: How to extract modules from large Zig files without sacrificing cohesion

**Key Insights**:
- Extract App-independent functions first (no App state dependencies)
- Evaluate state-heavy features separately (cost vs benefit)
- Use extraction checklist (5+ dependencies = keep in app.zig)
- Cohesion > arbitrary line count targets

**Extraction Checklist**:
```
Extract if:
- Function has no `self: *Self` parameter
- Logic is reusable
- Testable in isolation
- < 3 parameters needed

Keep in app.zig if:
- Needs 5+ app state fields
- Tightly coupled state transitions
- Would require "god struct" context
```

**Real-world example**: kaiu's file_ops.zig extraction
- ✅ Extracted: App-independent functions (copyDirRecursive, isValidFilename, formatDisplayPath)
- ❌ Not extracted: Search/preview (too state-dependent)

**Applicability**: Any large Zig codebase (or similar languages) where module splitting is needed

---

#### 2. `zig-symlink-safety-pattern.md`

**What it teaches**: Safe handling of symbolic links in recursive file operations

**Key Insights**:
- Use `readLink()` BEFORE `statFile()` to detect symlinks
- `statFile()` follows symlinks, so `stat.kind == .sym_link` never works
- Security risk: Following symlinks during deletion can delete files outside intended directory
- Preserve symlinks as symlinks during copy operations

**Critical Pattern**:
```zig
// ✅ CORRECT ORDER
if (std.fs.cwd().readLink(path, &buf)) |_| {
    try std.fs.cwd().deleteFile(path); // Delete symlink only
    return;
} else |_| {}

const stat = try std.fs.cwd().statFile(path); // Now safe to follow
```

**Security Example**:
```
/tmp/app/temp/ -> /etc/  (malicious symlink)

Without safety: statFile() follows symlink, then deleteTree() called on resolved path
With safety: readLink() detects symlink, deleteFile() removes symlink only → /etc untouched
```

**API Reference Table**:
| Function | Follows Symlinks? | Use Case |
|----------|-------------------|----------|
| `statFile()` | ✅ YES | Get target info |
| `readLink()` | ❌ NO | Detect symlink |
| `deleteFile()` | ❌ NO | Delete symlink itself |

**Applicability**: Any recursive file operations in Zig (and similar in other languages)

---

## Session Summary

### Refactoring Results

**Before**:
- app.zig: 2253 lines (mixed responsibilities)

**After**:
- app.zig: 1887 lines (-366 lines) - State management, event loop, search, preview
- file_ops.zig: 390 lines (new) - Pure file operations, utilities

**Extracted Functions** (9 total):
1. `isValidFilename()` - Path validation
2. `encodeBase64()` - OSC 52 encoding
3. `copyPath()` - File/directory copy
4. `copyDirRecursive()` - Recursive directory copy with symlink safety
5. `deletePathRecursive()` - Recursive delete with symlink safety
6. `formatDisplayPath()` - Home directory ~ replacement
7. `isBinaryContent()` - Binary file detection
8. `ClipboardOperation` enum - Yank/cut state

**Not Extracted** (intentionally):
- Search logic - Too tightly coupled to App state (mode, cursor, scroll, search_matches)
- Preview logic - Too tightly coupled to App state (preview_content, preview_scroll)

**Design Philosophy**:
> Cohesion over arbitrary line count targets. If extraction requires passing 5+ parameters or creates a "god struct," keep it together.

---

## Learned Patterns Index

All patterns now available in `.claude/skills/learned/`:

1. `zig-module-extraction-strategy.md` - [NEW] Module splitting strategy
2. `zig-symlink-safety-pattern.md` - [NEW] Symlink handling in file ops
3. `zig-file-operations-error-handling.md` - Error handling for file ops
4. `zig-tui-mode-based-input.md` - TUI input mode patterns
5. `track-separation-pattern.md` - Feature vs Technical track
6. `tui-file-explorer-conventions.md` - TUI file manager design
7. `command-based-track-declaration.md` - Track declaration pattern

---

## Next Steps

✅ Documentation updated
✅ Patterns extracted and saved
➡️ Ready for: `/pr` or continue with next task

---

**Generated by**: doc-updater agent
