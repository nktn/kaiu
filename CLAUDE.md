# CLAUDE.md

**kaiu** (回遊) - TUI file explorer in Zig with Vim keybindings.

## Commands

```bash
zig build                       # Build
zig build run                   # Build and run
zig build test                  # Run tests (silent on success)
zig build test --summary all    # Run tests with results
```

## Architecture

Model-View-Update pattern with libvaxis:

- `app.zig` - State + event handling
- `file_ops.zig` - File operations (copy, delete, path utilities, base64 encoding)
- `ui.zig` - Rendering
- `tree.zig` - FileTree data structure

See @.claude/rules/architecture.md for state machine and design decisions.

## Keybindings

Navigation: `j`/`k` move, `h` collapse/close, `l`/`Enter` expand/open, `gg`/`G` jump, `.` toggle hidden, `/` search, `?` help, mouse click/double-click.

File operations: `Space` mark, `y` yank, `d` cut, `p` paste, `D` delete, `r` rename, `a`/`A` create.

Other: `o` preview toggle, `c`/`C` clipboard, `q` quit, `--no-icons` flag to disable Nerd Font icons.

## Workflow

### Feature Track (User-facing features)
1. **Plan**: `/speckit.specify` → `/speckit.plan` → `/speckit.tasks`
2. **Implement**: `/implement` (runs TDD + build-fix + review)
3. **Review**: `/codex` → Decision Log in PR comments
4. **Merge**: `/pr merge`

### Technical Track (Refactoring, docs)
1. **Start**: `/technical "description"` or `/technical #22`
2. **Implement**: orchestrator → TDD → refactor
3. **Review**: `/codex-fix` → PR (Closes #XX)

**Track Selection**: "Does this change let users do something new?" → Yes = Feature Track, No = Technical Track

## References

| Topic | File |
|-------|------|
| Architecture & State | @.claude/rules/architecture.md |
| Security | @.claude/rules/security.md |
| Performance | @.claude/rules/performance.md |
| Agents & Decision Log | @.claude/rules/agents.md |
| Build Patterns | @.claude/skills/zig-build-engineer/SKILL.md |

## Constraints

- Ghostty terminal primary target
- Zero config philosophy
- Minimal file manager operations (mark, yank/cut/paste, delete with confirmation, rename, create)
