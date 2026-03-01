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
- **Discoverable** — Command palette (⌃Space) shows all features. No memorization required.

## Features

- **Fuzzy file finder** (Ctrl+O) — Quick open files by typing partial names
- Full mouse support (click, drag, scroll)
- Undo/redo
- Find and replace (regex supported)
- Text selection (keyboard and mouse) with column/block selection mode
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
| Ctrl+F | Find |
| Ctrl+R | Replace |
| Ctrl+G | Go to line |
| Ctrl+A | Select all |
| Ctrl+T | Toggle theme |
| Ctrl+P | Toggle Nerd Font glyphs |
| Ctrl+Space | Command palette |
| Ctrl+/ | Help |

All features are also accessible via the command palette (Ctrl+Space), keyboard shortcuts, and mouse.

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

### Column (Block) Selection

- Alt+Shift+Up/Down to enter column selection mode
- Alt+Click and Alt+Drag for mouse-driven column selection
- Rectangular selection with visual highlight (purple tint)
- Virtual whitespace: cursor can extend past line endings in column mode
- Type to insert on all selected lines simultaneously
- Backspace/Delete operate across the rectangle
- Columnar cut/copy/paste (paste distributes lines vertically)
- Status bar COL indicator shows selection dimensions
- Escape to exit column mode

### Search & Replace

- Find (Ctrl+F)
- Find next / previous (Ctrl+N / Ctrl+P)
- Replace (Ctrl+R)
- Replace all
- Search wraps around document

### User Interface

- Command palette (Ctrl+Space) — single entry point for all commands with type-to-filter
- Context-aware status bar with interactive, clickable pills
- Status bar pills adapt to terminal width via priority-based progressive disclosure
- Line numbers in gutter
- Modal dialogs for search, replace, go-to-line
- Footer prompts for simple inputs (Save As, confirmations)
- Escape dismisses overlays; final fallback opens command palette
- Minimap / vertical scrollbar with braille text density (Alt+M to toggle)
- Minimap shows viewport position and git change indicators
- File explorer tree panel (Ctrl+B to toggle)
  - Directory tree with expand/collapse, single-child dir collapsing
  - Fuzzy filter (/ to start, type to filter, Esc to clear)
  - Git status colors (modified, added, untracked, staged)
  - Sticky headers for scrolled-past ancestor directories
  - Scrollbar for large trees
  - Resizable panel ({ and } keys, or drag border with mouse)
  - File preview on cursor navigation (transient tabs)
  - Auto-reveals active file on tab switch

### Mouse Support

- Click to position cursor
- Click and drag to select
- Click on status bar pills to toggle/execute commands
- Click on command palette items to execute
- Scroll wheel for vertical scrolling
- Click or drag minimap to scroll document
- Click files in tree panel to open, drag border to resize

### Themes

- Dark theme (default)
- Light theme
- Switch via Ctrl+T or command palette
- True-color (24-bit RGB)

### Nerd Font Glyphs

- Enhanced UI with Nerd Font glyphs (rounded pills, icons)
- Toggle with Alt+I or command palette
- Automatically falls back to ASCII when disabled
- Disable by default: `--no-nerd-font` flag or `ZEPTO_NERD_FONT=0` env var

### Terminal Compatibility

- Works over SSH
- Handles terminal resize (SIGWINCH)
- Alternate screen buffer (restores terminal on exit)
- Bracketed paste mode
- SGR mouse reporting

## License

MIT
