# kaiu (回遊)

TUI file explorer with Vim keybindings, written in Zig.

## Features

- VSCode-like tree view with expand/collapse
- Vim-native navigation (hjkl, gg/G)
- Incremental search with highlighting
- File preview with line numbers
- Hidden files toggle
- Path navigation (go to path)
- Clipboard support (OSC 52)
- Mouse wheel scrolling

## Requirements

- Zig 0.14.0+
- Terminal with TUI support (recommended: Ghostty, Kitty, WezTerm)

## Installation

```bash
git clone https://github.com/nktn/kaiu.git
cd kaiu
zig build -Doptimize=ReleaseFast
# Binary is at zig-out/bin/kaiu
```

## Usage

```bash
kaiu              # Open current directory
kaiu ~/projects   # Open specific directory
kaiu ~/.config    # Tilde expansion supported
```

## Keybindings

### Navigation

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `h` / `←` | Collapse directory / go to parent |
| `l` / `→` / `Enter` | Expand directory / open preview |
| `gg` | Jump to top |
| `G` | Jump to bottom |
| `gn` | Go to path |

### Tree Operations

| Key | Action |
|-----|--------|
| `Tab` | Toggle expand current directory |
| `H` | Collapse all directories |
| `L` | Expand all directories |
| `.` | Toggle hidden files |
| `R` | Reload tree |

### Search

| Key | Action |
|-----|--------|
| `/` | Enter search mode |
| `n` | Next search match |
| `N` | Previous search match |
| `Esc` | Clear search |

### Other

| Key | Action |
|-----|--------|
| `o` | Toggle file preview |
| `c` | Copy full path to clipboard |
| `C` | Copy filename to clipboard |
| `?` | Show help |
| `q` | Quit |

## Project Structure

```
src/
├── main.zig    # Entry point, CLI argument handling
├── app.zig     # Application state, event loop, key handling
├── tree.zig    # FileTree data structure
└── ui.zig      # libvaxis rendering, search highlighting
```

## Architecture

See [.claude/rules/architecture.md](.claude/rules/architecture.md) for design decisions.

## License

MIT
