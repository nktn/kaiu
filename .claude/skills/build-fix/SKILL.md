---
name: build-fix
description: >
  Incrementally fix Zig build and compilation errors with minimal changes.
  トリガー: "build-fix", "ビルドエラー", "/build-fix"
---

# Zig Build Fix

Fix `zig build` errors one at a time with minimal diffs.

## Process

1. **Run build**
   ```bash
   zig build 2>&1
   ```

2. **Parse errors** - Group by file, prioritize by severity

3. **For each error:**
   - Show error context (file, line, message)
   - Explain the issue
   - Propose minimal fix
   - Apply fix
   - Re-run build
   - Verify error resolved

4. **Stop if:**
   - Fix introduces new errors
   - Same error persists after 3 attempts
   - User requests pause

5. **Show summary:**
   - Errors fixed
   - Errors remaining
   - Lines changed

## Common Zig Errors

| Error | Fix |
|-------|-----|
| `expected type 'X', found 'Y'` | Add `@intCast`, `@ptrCast`, or fix type |
| `error is ignored` | Add `try` or `catch` |
| `use of undeclared identifier` | Add import or fix spelling |
| `unable to evaluate comptime` | Use comptime value or allocator |
| `object is possibly null` | Add `orelse` or `if` check |

## Minimal Diff Rules

**DO:**
- Add type annotations
- Add error handling (try/catch)
- Fix imports
- Add casts

**DON'T:**
- Refactor unrelated code
- Change architecture
- Add features
- Optimize

## Example

```
Error: src/tree.zig:45:12: error: expected type 'usize', found 'u32'

Fix:
- const index: usize = entry.index;
+ const index: usize = @intCast(entry.index);

Lines changed: 1
```

## Related

- Agent: `.claude/agents/zig-build-resolver.md`
- Workflow: `/implement`
