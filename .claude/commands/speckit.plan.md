---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root and parse JSON for FEATURE_DIR, FEATURE_SPEC, IMPL_PLAN.

2. **Detect project type**: Check for `build.zig` at repo root.
   - If exists → **Zig project** → Use zig-architect workflow (see below)
   - Otherwise → Use standard workflow

3. **Load context**: Read FEATURE_SPEC and `specs/constitution.md`.

4. **Execute plan workflow** (based on project type).

5. **Stop and report**: Report FEATURE_DIR, IMPL_PLAN path, and generated artifacts.

## Zig Project Workflow

For Zig projects, use the `zig-architect` agent:

1. **Invoke zig-architect**: Use the Task tool with `subagent_type: zig-architect` to:
   - Read the spec at FEATURE_SPEC
   - Read existing architecture at `.claude/rules/architecture.md` (参照のみ)
   - Create plan.md at IMPL_PLAN with:
     - Technical Context (Zig version, libvaxis, etc.)
     - Constitution Check
     - Architecture decisions (state machine, memory strategy, modules)
     - Implementation phases aligned with User Story priorities

2. **Output**: plan.md のみ

**Note**: architecture.md の更新は `/implement` 実行時に行う (実装時に詳細が確定するため)

## Standard Workflow (Non-Zig)

1. **Load IMPL_PLAN template** and fill:
   - Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)

2. **Phase 0**: Generate research.md (resolve all NEEDS CLARIFICATION)

3. **Phase 1**: Generate data-model.md, contracts/, quickstart.md

4. **Phase 1**: Update agent context by running `.specify/scripts/bash/update-agent-context.sh claude`

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
