---
description: Verify tasks.md covers all spec requirements before implementation.
handoffs:
  - label: Fix Coverage Gaps
    agent: speckit.tasks
    prompt: Regenerate tasks to cover identified gaps
    send: true
  - label: Proceed to Implementation
    agent: speckit.implement
    prompt: Start implementation with verified tasks
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Verify that tasks.md comprehensively covers all requirements from spec.md before starting implementation. This command should run after `/speckit.tasks` to ensure no requirements are missed.

## Operating Constraints

**STRICTLY READ-ONLY**: Do **not** modify any files. Output a verification report with coverage matrix and gap analysis.

**Constitution Authority**: The project constitution (`.specify/memory/constitution.md`) principles are non-negotiable. Constitution conflicts are automatically CRITICAL.

## Execution Steps

### 1. Initialize Verification Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON for FEATURE_DIR and AVAILABLE_DOCS. Derive absolute paths:

- SPEC = FEATURE_DIR/spec.md
- TASKS = FEATURE_DIR/tasks.md
- CONSTITUTION = .specify/memory/constitution.md (optional)

Abort with an error message if spec.md or tasks.md is missing.

### 2. Load and Parse Artifacts

**From spec.md, extract:**

- User Stories (US1, US2, ...) with priorities (P1, P2, P3)
- Acceptance Criteria (AC1.1, AC1.2, ...)
- Functional Requirements (FR1, FR2, ...)
- Non-Functional Requirements (NFR1, NFR2, ...)
- Success Criteria (SC1, SC2, ...)
- Out of Scope items (if present)

**From tasks.md, extract:**

- Task IDs (T001, T002, ...)
- Story labels ([US1], [US2], ...)
- Phase groupings
- File paths mentioned

**From constitution.md (if exists), extract:**

- MUST principles
- SHOULD principles

### 3. Build Coverage Matrix

For each requirement, find associated tasks:

1. **Explicit Match**: Task has [US1] label for User Story 1
2. **Keyword Match**: Task description contains requirement keywords
3. **File Match**: Task file path relates to requirement domain

Create mapping:

```
Requirement → [Task IDs] → Coverage Status
```

### 4. Detect Gaps

Identify:

1. **Uncovered Requirements**: Requirements with no associated tasks
2. **Partial Coverage**: Requirements with tasks but missing acceptance criteria
3. **Orphan Tasks**: Tasks not linked to any requirement
4. **Priority Misalignment**: P1 requirements in late phases
5. **Constitution Violations**: Tasks conflicting with MUST principles

### 5. Severity Assignment

- **CRITICAL**: Uncovered User Story, Constitution MUST violation
- **HIGH**: Uncovered Acceptance Criteria, Untestable Success Criteria
- **MEDIUM**: Orphan tasks, Priority misalignment
- **LOW**: Missing explicit labels (but functionally covered)

### 6. Generate Report

Output a structured Markdown report:

```markdown
# Task Coverage Verification Report

## Summary

| Metric | Value |
|--------|-------|
| Total User Stories | X |
| Covered | Y |
| Coverage Rate | Z% |
| Critical Gaps | N |

## Coverage Matrix

| Requirement | Type | Priority | Tasks | Status |
|-------------|------|----------|-------|--------|

## Gaps (Action Required)

### CRITICAL
...

### HIGH
...

## Task Suggestions

Based on gaps, suggested additions:
...

## Next Actions
- [ ] ...
```

### 7. Provide Recommendations

- If CRITICAL gaps: Recommend fixing before `/speckit.implement`
- If only LOW/MEDIUM: User may proceed with awareness
- Provide specific task suggestions for each gap

## Example Output

```markdown
# Task Coverage Verification Report

## Summary

| Metric | Value |
|--------|-------|
| Total User Stories | 5 |
| Covered | 4 |
| Coverage Rate | 80% |
| Critical Gaps | 1 |

## Coverage Matrix

| Requirement | Type | Priority | Tasks | Status |
|-------------|------|----------|-------|--------|
| US1: Directory Navigation | Story | P1 | T001-T005 | COVERED |
| US2: File Preview | Story | P1 | T006-T008 | COVERED |
| US3: Search | Story | P2 | - | GAP |
| AC1.1: j/k moves cursor | AC | - | T002 | COVERED |
| AC3.1: / opens search | AC | - | - | GAP |

## Gaps (Action Required)

### CRITICAL

1. **US3: Search functionality has no tasks**
   - Requirement: User can search files by name
   - Impact: P2 feature completely missing
   - Suggested: Add Phase 5 with search tasks

## Task Suggestions

1. T015 [US3] Implement search input handler in src/app.zig
2. T016 [US3] Create search highlighting in src/ui.zig
3. T017 [US3] Add n/N navigation for search results

## Next Actions

- [ ] Run /speckit.tasks to add US3 coverage
- [ ] Or manually add search tasks to tasks.md

---
Recommendation: Resolve CRITICAL gap before /speckit.implement
```

## Context

$ARGUMENTS
