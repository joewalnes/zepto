# Zepto

A minimal terminal text editor in a single file.

## Quick Start

```bash
mkdir -p ~/.local/bin && curl -fsSL https://github.com/joewalnes/zepto/releases/download/latest/zepto -o ~/.local/bin/zepto && chmod +x ~/.local/bin/zepto
```

Then run `zepto myfile.txt`. Or [download manually](https://github.com/joewalnes/zepto/releases/download/latest/zepto).

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

- **Fuzzy file finder** (Ctrl+O) — Quick open files by typing partial names
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
| Ctrl+N | New file |
| Ctrl+O | Open file (fuzzy finder) |
| Ctrl+S | Save |
| Ctrl+Q | Quit |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+X/C/V | Cut/Copy/Paste |
| Ctrl+F | Find (live) |
| Ctrl+R | Replace (live) |
| Ctrl+J/K | Find next/previous |
| Ctrl+G | Go to line |
| Ctrl+A | Select all |
| Alt+↑/↓ | Move line up/down |

All features are also accessible via keyboard shortcuts, menu bar, and mouse.

## Requirements

- Perl 5.10+ (standard library only, no CPAN modules)
- Any terminal with ANSI support

## Building from Source

```bash
make build    # Creates single-file 'zepto' executable
make test     # Run tests
```

## Full Feature List

### File Operations

- New file (Ctrl+N)
- Open file with fuzzy finder (Ctrl+O)
- Open file from command line
- Create new file if doesn't exist
- Save (Ctrl+S)
- Save and quit (Ctrl+W)
- Quit with unsaved changes protection (Ctrl+Q, double-tap to force)
- Modified indicator in status bar
- Save/Discard prompt for unsaved changes

### Text Editing

- Insert, delete, backspace
- Undo / redo (Ctrl+Z / Ctrl+Y)
- Cut, copy, paste (Ctrl+X / Ctrl+C / Ctrl+V) with system clipboard integration
- Auto-indent on newline
- Tab key inserts spaces
- Indent / unindent selected block (Tab / Shift+Tab)
- Move line(s) up/down (Alt+↑ / Alt+↓)
- Duplicate line(s) up/down (Alt+Shift+↑ / Alt+Shift+↓)

### Navigation

- Arrow keys
- Home / End (start/end of line)
- Page Up / Page Down
- Ctrl+Home / Ctrl+End (start/end of file)
- Go to line number (Ctrl+G)
- Mouse click to position cursor
- Mouse wheel scrolling

### Selection

- Shift+arrow keys to select
- Ctrl+A to select all
- Click and drag to select
- Typing replaces selection
- Cut/copy/paste work with selection

### Search & Replace

- **Live interactive find** (Ctrl+F) — Search with instant highlighting
- **Live find & replace** (Ctrl+R) — Replace with live preview
- Regex search enabled by default (PCRE syntax)
- Case insensitive by default
- Toggle regex mode (Alt+R or click [.*])
- Toggle case sensitivity (Alt+I or click [Aa])
- Navigate matches with ↑/↓ arrow keys
- Find next / previous (Ctrl+J / Ctrl+K)
- Enter to replace all matches
- Current match highlighted distinctly
- Match count shown in footer

### User Interface

- Menu bar with mouse support
- Quick access buttons (Open, Save, Quit) in menu bar
- Dropdown menus with keyboard navigation
- Line numbers in gutter
- Status bar (filename, position, modified state)
- Modal dialogs for search, replace, go-to-line
- Footer prompts for simple inputs (Save As, confirmations)
- Escape closes menus and dialogs

### Mouse Support

- Click to position cursor
- Click and drag to select
- Click on menus to open
- Click on menu items to activate
- Scroll wheel for vertical scrolling

### Themes

- Dark theme (default)
- Light theme
- Switch via View menu
- True-color (24-bit RGB)

### Terminal Compatibility

- Works over SSH
- Handles terminal resize (SIGWINCH)
- Alternate screen buffer (restores terminal on exit)
- Bracketed paste mode
- SGR mouse reporting

## License

MIT
