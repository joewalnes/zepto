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

- Open file from command line
- Create new file if doesn't exist
- Save (Ctrl+S)
- Save and quit (Ctrl+W)
- Quit with unsaved changes protection (Ctrl+Q, double-tap to force)
- Modified indicator in status bar

### Text Editing

- Insert, delete, backspace
- Undo / redo (Ctrl+Z / Ctrl+Y)
- Cut, copy, paste (Ctrl+X / Ctrl+C / Ctrl+V)
- Auto-indent on newline
- Tab key inserts spaces
- Indent / unindent selected block (Tab / Shift+Tab)

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

- Find (Ctrl+F)
- Find next / previous (Ctrl+N / Ctrl+P)
- Replace (Ctrl+R)
- Replace all
- Search wraps around document

### User Interface

- Menu bar with mouse support
- Dropdown menus with keyboard navigation
- Line numbers in gutter
- Status bar (filename, position, modified state)
- Modal dialogs for search, replace, go-to-line
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
