---
description: Enforce test-driven development for Zig. Write failing tests FIRST, then implement minimal code to pass.
---

# Zig TDD

Enforce Red-Green-Refactor cycle using Zig's built-in testing.

## TDD Cycle

```
RED    → Write failing test
GREEN  → Implement minimal code to pass
REFACTOR → Improve while tests pass
REPEAT → Next test case
```

## Process

1. **Define Interface** - Types and function signatures
2. **Write Failing Test** (RED)
   ```zig
   test "function does X" {
       const result = try functionUnderTest(input);
       try std.testing.expectEqual(expected, result);
   }
   ```

3. **Run Test** - Verify it fails
   ```bash
   zig build test
   ```

4. **Implement** (GREEN) - Minimal code to pass

5. **Run Test** - Verify it passes

6. **Refactor** - Improve code, keep tests passing

7. **Check Coverage** - Add edge case tests

## Test Template

```zig
const std = @import("std");
const testing = std.testing;
const module = @import("module.zig");

test "happy path" {
    const result = try module.function(valid_input);
    try testing.expectEqual(expected, result);
}

test "handles null" {
    const result = module.function(null);
    try testing.expectError(error.InvalidInput, result);
}

test "handles empty" {
    const result = try module.function(&[_]u8{});
    try testing.expectEqual(0, result.len);
}

test "memory cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();  // Detects leaks

    const obj = try module.create(gpa.allocator());
    defer obj.deinit();
    // ...
}
```

## Edge Cases to Test

- [ ] Null/optional input
- [ ] Empty collections
- [ ] Boundary values (0, max)
- [ ] Error conditions
- [ ] Memory allocation failure
- [ ] Unicode/special characters

## Commands

```bash
zig build test                    # Run all tests
zig build test -- --verbose       # Verbose output
zig test src/file.zig --test-filter "name"  # Filter tests
```

## Integration with Speckit

Use during `/speckit.implement` when tasks.md indicates TDD approach:
1. For each task in tasks.md, apply Red-Green-Refactor
2. Mark task `[X]` only after tests pass

## Related

- Agent: `.claude/agents/zig-tdd.md`
- Workflow: `/speckit.implement`
