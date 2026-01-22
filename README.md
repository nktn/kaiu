# kaiu (回遊)

TUI file explorer with Vim keybindings, written in Zig.

## Features

- VSCode-like tree view with expand/collapse
- Vim-native navigation (j/k/h/l)
- File preview pane
- Hidden files toggle
- Kitty Graphics Protocol support (Ghostty)

## Requirements

- Zig (latest stable)
- Terminal with Kitty Graphics Protocol support (recommended: Ghostty)

## Build

```bash
zig build           # Build
zig build run       # Build and run
zig build test      # Run tests
```

## Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `h` | Close preview / collapse directory |
| `l` / `Enter` | Open preview / expand directory |
| `a` | Toggle hidden files |
| `q` | Quit |

## Project Structure

```
src/
├── main.zig    # Entry point
├── app.zig     # Application state, event loop
├── tree.zig    # FileTree data structure
└── ui.zig      # libvaxis rendering
```

## License

MIT
