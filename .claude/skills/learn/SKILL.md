---
name: learn
description: >
  Extract reusable Zig patterns from current session and save as skills.
  トリガー: "learn", "パターン保存", "/learn"
---

# Zig Learn

Analyze the session and extract Zig patterns worth saving.

## What to Extract

1. **Error Resolution Patterns**
   - Zig-specific compiler errors
   - libvaxis quirks
   - Build system issues

2. **Debugging Techniques**
   - Memory leak detection
   - Comptime debugging
   - Test strategies

3. **Workarounds**
   - Library limitations
   - Platform-specific fixes
   - Version quirks

4. **Zig Idioms**
   - Allocator patterns
   - Error handling patterns
   - Comptime tricks

## Output Format

Save to `.claude/skills/learned/[pattern-name].md`:

```markdown
---
name: [pattern-name]
description: [When to use this pattern]
---

# [Descriptive Pattern Name]

**Extracted:** [Date]
**Context:** [When this applies]

## Problem
[What problem this solves]

## Solution
```zig
// Zig code demonstrating the pattern
```

## When to Use
[Trigger conditions]

## Related
- [Links to related docs/issues]
```

## Process

1. Review session for extractable Zig patterns
2. Identify most valuable insight
3. Draft skill file
4. Ask user to confirm
5. Save to `.claude/skills/learned/`

## Good Candidates

- Non-obvious compiler error fixes
- libvaxis usage patterns
- Memory management strategies
- Cross-compilation solutions
- Build.zig patterns

## Skip

- Trivial typo fixes
- One-time issues
- Generic programming advice
