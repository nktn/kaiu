---
description: Verify implementation satisfies spec requirements after implementation.
handoffs:
  - label: Add Missing Tasks
    agent: speckit.tasks
    prompt: Add tasks for identified implementation gaps
    send: true
  - label: Continue Implementation
    agent: speckit.implement
    prompt: Continue with additional tasks
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

Supported arguments:

- `--phase=N` - Verify specific phase only
- `--story=USn` - Verify specific user story only
- (no args) - Full verification of all requirements

## Goal

Verify that the implementation code satisfies all requirements from spec.md. This command should run after implementation phases or at the end of `/speckit.implement` to ensure the code matches the specification.

## Operating Constraints

**STRICTLY READ-ONLY**: Do **not** modify any files. Output a verification report with implementation status and gap analysis.

**Code Analysis Only**: Analyze existing code patterns without executing or modifying them.

## Execution Steps

### 1. Initialize Verification Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks` from repo root and parse JSON for FEATURE_DIR. Derive absolute paths:

- SPEC = FEATURE_DIR/spec.md
- TASKS = FEATURE_DIR/tasks.md

If `--phase` or `--story` argument provided, filter verification scope accordingly.

### 2. Load Specification

**From spec.md, extract:**

- Functional Requirements (FR1, FR2, ...) with keywords
- Acceptance Scenarios (AS1, AS2, ...) with expected behavior
- Success Criteria (SC1, SC2, ...) with measurable outcomes
- Out of Scope items (OS1, OS2, ...)
- User Stories for context

### 3. Scan Implementation

Scan the codebase for implementation evidence:

**For Zig projects:**

```
src/**/*.zig - Source files
build.zig - Build configuration
```

**Detection patterns:**

- Function definitions: `pub fn function_name(`
- Key handlers: `'x' =>`
- Struct definitions: `pub const StructName = struct`
- Test blocks: `test "test name"`
- Error handling: `catch`, `orelse`, error sets

### 4. Build Implementation Matrix

For each requirement, determine implementation status:

1. **IMPLEMENTED**: Code exists that fulfills the requirement
2. **PARTIAL**: Some aspects implemented, others missing
3. **MISSING**: No implementation found
4. **TESTED**: Implementation has associated tests

Mapping structure:

```
Requirement → Implementation Location → Test Location → Status
```

### 5. Analyze Test Coverage

For each User Story, analyze test coverage:

- Count test blocks related to the story
- Identify untested code paths
- Check for edge case coverage

### 6. Out of Scope Check

Scan for out-of-scope functionality that shouldn't exist:

**Common patterns to detect:**

- File modification functions (delete, move, copy, write)
- Network access (if not in scope)
- External process execution (if not in scope)

### 7. Generate Report

Output a structured Markdown report:

```markdown
# Implementation Verification Report

## Scope

[Full verification / Phase N / User Story USn]

## Summary

| Metric | Value |
|--------|-------|
| Total Requirements | X |
| Implemented | Y |
| Rate | Z% |
| Tested | N |
| Critical Missing | M |

## Implementation Matrix

| Requirement | Status | Location | Test | Notes |
|-------------|--------|----------|------|-------|

## Missing Implementations

### CRITICAL
...

## Out of Scope Check

| Item | Status |
|------|--------|

## Test Coverage

| User Story | Tasks | Tests | Coverage |
|------------|-------|-------|----------|

## Suggested Tasks
...

## Next Actions
- [ ] ...
```

### 8. Provide Recommendations

- If CRITICAL missing: Recommend adding tasks
- If tests missing: Suggest test tasks
- If out-of-scope detected: Flag for removal

## Partial Verification Mode

When `--phase` or `--story` is specified:

1. Filter requirements to those relevant to the phase/story
2. Verify only the filtered subset
3. Output "Ready for Next Phase" status if all pass
4. List blocking issues if any fail

## Example Output (Full Verification)

```markdown
# Implementation Verification Report

## Scope

Full verification (all requirements)

## Summary

| Metric | Value |
|--------|-------|
| Total Requirements | 15 |
| Implemented | 14 |
| Implementation Rate | 93% |
| Tested | 10 |
| Test Rate | 67% |
| Critical Missing | 0 |
| Warnings | 3 |

## Implementation Matrix

| Requirement | Status | Location | Test | Notes |
|-------------|--------|----------|------|-------|
| FR1: Directory expand | DONE | tree.zig:45 | YES | toggleExpand() |
| FR2: File preview | DONE | app.zig:220 | YES | openPreview() |
| FR3: Cursor navigation | DONE | app.zig:150 | NO | Needs test |
| AS1: l key expands | DONE | app.zig:300 | YES | in handleKey |
| SC1: Performance <1s | NOT VERIFIED | - | NO | Need benchmark |

## Missing Implementations

(none)

## Warnings

1. **FR3: Cursor navigation has no test**
   - Implementation: app.zig:150 moveCursor()
   - Suggested: Add test "moveCursor handles boundaries"

2. **SC1: Performance not verified**
   - Criteria: 1000 files in <1 second
   - Suggested: Add benchmark test

## Out of Scope Check

| Item | Status |
|------|--------|
| File editing | OK - Not found |
| File deletion | OK - Not found |
| Network access | OK - Not found |

## Test Coverage by User Story

| User Story | Implementation | Tests | Coverage |
|------------|---------------|-------|----------|
| US1: Navigation | 100% | 80% | 4/5 |
| US2: Preview | 100% | 100% | 3/3 |
| US3: Search | 100% | 60% | 3/5 |

## Suggested Tasks

1. T030 Add test for cursor boundary handling
2. T031 Add performance benchmark test
3. T032 Add test for search edge cases

## Next Actions

- [ ] Add missing tests (3 tasks suggested)
- [ ] Verify performance criteria with benchmark

---
Verification completed: 0 CRITICAL, 3 WARNINGS
Implementation ready for PR (consider adding suggested tests)
```

## Example Output (Partial Verification)

```markdown
# Implementation Verification Report

## Scope

Phase 3 / User Story US1 (Directory Navigation)

## Summary

| Metric | Value |
|--------|-------|
| US1 Requirements | 5 |
| Implemented | 5 |
| Rate | 100% |
| Tested | 4 |

## US1 Implementation Status

| Requirement | Status | Location |
|-------------|--------|----------|
| AC1.1: j/k cursor | DONE | app.zig:150 |
| AC1.2: l expands | DONE | app.zig:180 |
| AC1.3: h collapses | DONE | app.zig:200 |
| AC1.4: Enter opens | DONE | app.zig:220 |
| AC1.5: . toggle hidden | DONE | app.zig:240 |

## Ready for Next Phase: YES

All US1 acceptance criteria verified.
Proceed to Phase 4 (US2: File Preview).
```

## Context

$ARGUMENTS
