# CLAUDE.md

**kaiu** (回遊) - TUI file explorer in Zig with Vim keybindings.

## Commands

```bash
zig build           # Build
zig build run       # Build and run
zig build test      # Run tests
```

## Architecture

Model-View-Update pattern with libvaxis:

- `app.zig` - State + event handling
- `ui.zig` - Rendering
- `tree.zig` - FileTree data structure

See @.claude/rules/architecture.md for state machine and design decisions.

## Keybindings

`j`/`k` move, `h` collapse/close, `l`/`Enter` expand/open, `.` toggle hidden, `o` preview toggle, `q` quit.

## Workflow

1. **Plan**: `/speckit.specify` → `/speckit.plan` → `/speckit.tasks`
2. **Implement**: `/implement` (runs TDD + build-fix + review)
3. **Review**: `/codex` → Decision Log in PR comments
4. **Merge**: `/pr merge`

## References

| Topic | File |
|-------|------|
| Architecture & State | @.claude/rules/architecture.md |
| Security | @.claude/rules/security.md |
| Performance | @.claude/rules/performance.md |
| Agent Usage | @.claude/rules/agents.md |
| Build Patterns | @.claude/skills/zig-build-engineer/SKILL.md |

## Constraints

- Not a file manager (no copy/move/delete)
- Ghostty terminal primary target
- Zero config philosophy
