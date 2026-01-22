# kaiu

TUI file explorer written in Zig with Vim keybindings.

## Commands

```bash
zig build           # Build
zig build run       # Run
zig build test      # Test
```

## Architecture

Model-View-Update pattern with libvaxis rendering.

@.claude/rules/architecture.md

## Development Workflow

```
/speckit.specify → /speckit.plan → /speckit.tasks → /implement → /pr → /codex
```

## Key Skills

| Skill | Description |
|-------|-------------|
| `/implement` | Zig TDD implementation with orchestrator |
| `/tdd` | Red-Green-Refactor cycle |
| `/build-fix` | Fix compilation errors minimally |
| `/pr` | Create/manage Pull Requests |
| `/codex` | Code review via Codex CLI |

## Decision Log Rule

Record review decisions in PR comments:

```markdown
## Decision Log
### [Issue] (Severity - Adopted/Skipped)
**Issue**: What was pointed out
**Decision**: What to do
**Rationale**: Why
```

## Guidelines

@.claude/rules/security.md
@.claude/rules/performance.md

## What kaiu is NOT

- Not a file manager (no copy/move/delete)
- Not an IDE
