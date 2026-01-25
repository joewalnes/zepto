# Zepto

A minimal terminal text editor in a single file.

## Why Zepto?

Sometimes you just need to edit a file. You're SSH'd into a server, inside a Docker container, or
on a fresh machine with nothing installed. You need something minimal, intuitive, no-learning curve,
and easy to install.

Zepto is a single file. Just copy and run it. 

Zepto is:

- **One file** — Copy it anywhere. No installation, no dependencies, no config.
- **Familiar** — Familiar keybindings (Ctrl+S, Ctrl+Z, Ctrl+C/V). Mouse enabled. No modes to learn.
- **Discoverable** — Menu bar shows all features. No memorization required.

## Features

- Full mouse support (click, drag, scroll)
- Undo/redo
- Find and replace (regex supported)
- Text selection (keyboard and mouse)
- Line numbers
- Dark and light themes
- Go to line
- Works over SSH

## Usage

```bash
zepto myfile.txt
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+S | Save |
| Ctrl+Q | Quit |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+X/C/V | Cut/Copy/Paste |
| Ctrl+F | Find |
| Ctrl+R | Replace |
| Ctrl+G | Go to line |
| Ctrl+A | Select all |
| Ctrl+/ | Help |

All features are also accessible via keyboard shortcuts, menu bar, and mouse.
