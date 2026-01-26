---
name: ghostty-terminal-detection
description: Reliable terminal emulator detection for feature enablement
---

# Ghostty Terminal Detection Pattern

**Extracted:** 2026-01-26
**Context:** Need to enable/disable features based on terminal capabilities

## Problem

Different terminal emulators support different features:
- Kitty Graphics Protocol (Kitty, Ghostty, WezTerm)
- OSC 52 clipboard (most modern terminals)
- True color support (most, but not all)
- Mouse support (varies)

Detecting the terminal emulator reliably is necessary to:
1. Enable advanced features when available
2. Provide graceful fallbacks
3. Avoid sending unsupported escape sequences

## Solution

### Environment Variable Detection

```zig
pub fn detectTerminal() TerminalType {
    const term = std.posix.getenv("TERM") orelse return .unknown;
    const term_program = std.posix.getenv("TERM_PROGRAM");

    // Ghostty sets TERM to "xterm-ghostty"
    if (std.mem.indexOf(u8, term, "ghostty") != null) {
        return .ghostty;
    }

    // Kitty sets TERM_PROGRAM to "kitty"
    if (term_program) |prog| {
        if (std.mem.eql(u8, prog, "kitty")) {
            return .kitty;
        }
        if (std.mem.eql(u8, prog, "WezTerm")) {
            return .wezterm;
        }
    }

    // Fallback: check TERM value
    if (std.mem.eql(u8, term, "xterm-256color")) {
        return .xterm;
    }
    if (std.mem.indexOf(u8, term, "screen") != null) {
        return .tmux; // or screen
    }

    return .unknown;
}
```

### Feature Detection Matrix

| Terminal | TERM | TERM_PROGRAM | Kitty Graphics | OSC 52 |
|----------|------|--------------|----------------|--------|
| Ghostty | `xterm-ghostty` | - | Yes | Yes |
| Kitty | `xterm-kitty` | `kitty` | Yes | Yes |
| WezTerm | `wezterm` | `WezTerm` | Partial | Yes |
| iTerm2 | `xterm-256color` | `iTerm.app` | No | Yes |
| Terminal.app | `xterm-256color` | `Apple_Terminal` | No | No |

### Capability-Based Approach (Preferred)

Instead of terminal detection, detect capabilities:

```zig
pub const TerminalCapabilities = struct {
    supports_kitty_graphics: bool,
    supports_osc52: bool,
    supports_true_color: bool,
    supports_mouse: bool,

    pub fn detect() TerminalCapabilities {
        return .{
            .supports_kitty_graphics = detectKittyGraphics(),
            .supports_osc52 = detectOSC52(),
            .supports_true_color = detectTrueColor(),
            .supports_mouse = true, // Assume yes, most support it
        };
    }
};

fn detectKittyGraphics() bool {
    const term = std.posix.getenv("TERM") orelse return false;
    const term_program = std.posix.getenv("TERM_PROGRAM");

    // Ghostty or Kitty
    if (std.mem.indexOf(u8, term, "ghostty") != null) return true;
    if (term_program) |prog| {
        if (std.mem.eql(u8, prog, "kitty")) return true;
        // WezTerm has partial support - check version if needed
    }

    return false;
}

fn detectOSC52() bool {
    const term_program = std.posix.getenv("TERM_PROGRAM");

    // Most modern terminals support OSC 52
    // Known exceptions: old versions of Terminal.app
    if (term_program) |prog| {
        if (std.mem.eql(u8, prog, "Apple_Terminal")) {
            // Check TERM_PROGRAM_VERSION if needed
            return false;
        }
    }

    return true; // Assume yes for most terminals
}
```

## When to Use

**Use environment variable detection when:**
- Enabling terminal-specific features (Kitty Graphics)
- Working around known bugs in specific terminals
- Optimizing for terminal-specific escape sequences

**Use capability detection when:**
- Feature support varies within terminal families
- Need forward compatibility with new terminals
- Fallback behavior is well-defined

## Pitfalls

### Don't Rely on TERM Alone
- Many terminals set `TERM=xterm-256color` (iTerm2, Alacritty, etc.)
- Use `TERM_PROGRAM` for disambiguation

### SSH/Tmux Complication
```bash
# TERM gets overridden in SSH sessions
ssh user@host  # TERM becomes xterm or screen-256color
tmux attach    # TERM becomes screen-256color or tmux-256color
```
- Original terminal capabilities are lost
- Ghostty detection fails inside tmux
- Solution: Store capabilities in separate env var or config file

### Version-Specific Features
```zig
// Some features require minimum version
fn supportsKittyGraphicsRGBA() bool {
    const term_program = std.posix.getenv("TERM_PROGRAM");
    const version = std.posix.getenv("TERM_PROGRAM_VERSION");

    if (term_program) |prog| {
        if (std.mem.eql(u8, prog, "kitty")) {
            // RGBA format added in Kitty 0.20.0
            if (version) |v| {
                return compareVersion(v, "0.20.0") >= 0;
            }
        }
    }
    return false;
}
```

## Implementation Pattern

```zig
// app.zig or main.zig
pub const App = struct {
    terminal_caps: TerminalCapabilities,

    pub fn init(allocator: Allocator) !*App {
        const caps = TerminalCapabilities.detect();

        const app = try allocator.create(App);
        app.* = .{
            .terminal_caps = caps,
            // ... other fields
        };

        return app;
    }

    fn showImagePreview(self: *App, path: []const u8) !void {
        if (self.terminal_caps.supports_kitty_graphics) {
            try self.showImageKittyGraphics(path);
        } else {
            try self.showImageASCII(path); // Fallback
        }
    }
};
```

## Testing

```zig
test "detect Ghostty" {
    try std.posix.setenv("TERM", "xterm-ghostty", 1);
    defer std.posix.unsetenv("TERM");

    const caps = TerminalCapabilities.detect();
    try std.testing.expect(caps.supports_kitty_graphics);
}

test "detect Kitty" {
    try std.posix.setenv("TERM", "xterm-kitty", 1);
    try std.posix.setenv("TERM_PROGRAM", "kitty", 1);
    defer {
        std.posix.unsetenv("TERM");
        std.posix.unsetenv("TERM_PROGRAM");
    }

    const caps = TerminalCapabilities.detect();
    try std.testing.expect(caps.supports_kitty_graphics);
}
```

## References

- [Terminal Environment Variables](https://www.gnu.org/software/gettext/manual/html_node/sh-envvars.html)
- [Ghostty Documentation](https://ghostty.org)
- [Kitty Terminal Info](https://sw.kovidgoyal.net/kitty/overview/#terminal-description)

## Related Patterns

- `.claude/skills/learned/kitty-graphics-rgba-transmit.md` - Using detected capabilities
- OSC 52 clipboard pattern (not yet documented)
