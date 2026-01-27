# kaiu (回遊)

TUI file explorer with Vim keybindings, written in Zig.

## Features

- VSCode-like tree view with expand/collapse
- Vim-native navigation (hjkl, gg/G)
- Incremental search with highlighting
- File preview with line numbers
- Hidden files toggle
- File operations (mark, yank/cut/paste, delete, rename, create)
- Clipboard support (OSC 52)
- Mouse wheel scrolling
- **VCS integration** - JuJutsu / Git status colors and branch display (JJ preferred when both exist)
- **Image preview** - PNG, JPG, GIF, WebP via Kitty Graphics Protocol
- **Drag & drop** - Drop files from Finder to copy into current directory (ASCII filenames only)
- **File watching** - Auto-refresh on external file changes

## Requirements

- Zig 0.15.2+
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

### File Operations

| Key | Action |
|-----|--------|
| `Space` | Toggle mark current file/directory |
| `y` | Yank (copy) marked files or current file |
| `d` | Cut marked files or current file |
| `p` | Paste yanked/cut files |
| `D` | Delete marked files or current file (with confirmation) |
| `r` | Rename current file/directory |
| `a` | Create new file in current directory |
| `A` | Create new directory in current directory |

### VCS & External Tools

| Key | Action |
|-----|--------|
| `gv` | Cycle VCS mode (Auto → JJ → Git → Auto) |
| `W` | Toggle file watching (auto-refresh on external changes) |

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
├── main.zig     # Entry point, CLI argument handling
├── app.zig      # Application state, event loop, key handling
├── file_ops.zig # File operations (copy, delete, clipboard)
├── tree.zig     # FileTree data structure
├── ui.zig       # libvaxis rendering, search highlighting
├── vcs.zig      # VCS integration (JuJutsu/Git status detection)
├── image.zig    # Image format detection and dimensions
├── watcher.zig  # File system watching (mtime polling)
└── kitty_gfx.zig # Kitty Graphics Protocol for image display
```

## Architecture

See [.claude/rules/architecture.md](.claude/rules/architecture.md) for design decisions.

## Known Limitations

### Drag & Drop

- **Non-ASCII filenames**: Drag & drop only works with ASCII filenames due to libvaxis bracketed paste implementation limitations
  - libvaxis converts some UTF-8 multibyte characters to U+FFFD (replacement character) during paste events
  - **Workaround**: Use kaiu's internal yank/paste (`y`/`p`) for files with non-ASCII names
  - Related: [bemenu #410](https://github.com/Cloudef/bemenu/issues/410)

## License

MIT
