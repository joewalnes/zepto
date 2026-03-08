# Zepto Design Document

Technical decisions, architecture, and rationale.

## Design Goals

1. **Single-file distribution** — The entire editor ships as one file you can copy anywhere.
2. **Zero dependencies** — Perl standard library only. No CPAN, no external tools.
3. **Instant startup** — Under 100ms to first render.
4. **Predictable behavior** — No modes, no surprises. Works like every other text field you've used.
5. **Testable architecture** — Clean separation enables comprehensive automated testing.

## Why Perl?

Perl is the most portable scripting language for system environments:

| Language | Availability                                       | Single-file? | Terminal support   |
|----------|----------------------------------------------------|--------------|--------------------|
| Perl     | Everywhere (POSIX, macOS, all Linux distros, BSDs) | Yes          | Excellent (termios)|
| Python   | Common but version fragmentation (2 vs 3)          | Harder       | Good               |
| Bash     | Everywhere but limited for complex apps            | Yes          | Limited            |
| Ruby     | Often missing on minimal systems                   | Yes          | Good               |
| Go/Rust  | Requires compilation per platform                  | Binary       | Excellent          |

Perl 5.10+ is installed by default on virtually every Unix-like system. It has:
- Native POSIX terminal control (termios)
- Excellent UTF-8 support
- Fast startup (~20ms)
- No compilation step

The tradeoff: Perl isn't fashionable. But for a tool that needs to work everywhere with zero setup,
it's the pragmatic choice.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  Editor                                      │
│              (event loop, state machine, dispatch, key bindings)             │
├──────────────────┬──────────────────┬─────────────────┬──────────────────────┤
│     Commands     │     Palette      │ CommandRegistry  │    Preferences      │
│ (editing ops,    │ (command palette,│ (command table,  │ (user settings,     │
│  file I/O, find) │  file picker,    │  shortcut map,   │  change callbacks)  │
│                  │  find-in-files)  │  fuzzy filter)   │                     │
├──────────────────┴──────────────────┴─────────────────┴──────────────────────┤
│  View        │ FindEngine     │ FileTree       │ FileSearchEngine            │
│ (viewport,   │ (incremental   │ (file explorer │ (cross-file grep via        │
│  cursor,     │  search with   │  with lazy     │  git grep / rg / perl)      │
│  selection)  │  background)   │  loading)      │                             │
├──────────────┴────────────────┴────────────────┴─────────────────────────────┤
│   Document         │ Highlighter      │ Diff          │ WrapMap / LineMap    │
│ (file I/O, undo,   │ (syntax dispatch │ (Myers diff   │ (word wrap, inline   │
│  redo, VCS status)  │  + line cache)   │  for gutter)  │  diff expansion)    │
├─────────────────────┴──────────────────┴───────────────┴─────────────────────┤
│                                  Buffer                                      │
│                     (gap buffer text storage, line index)                    │
├────────────────────────────────┬─────────────────────────────────────────────┤
│          Renderer              │               Terminal                      │
│ (state → ANSI escape codes,   │  (raw mode, I/O, clipboard,                │
│  minimap, tab bar, status bar) │   size detection, mouse tracking)          │
├────────────────────────────────┴─────────────────────────────────────────────┤
│  InputParser     │  InputWidget      │  Theme          │ Chars / Config     │
│ (bytes → events, │ (text input for   │ (semantic color │ (Nerd Font glyphs, │
│  CSI u support)  │  find, palette)   │  definitions)   │  global settings)  │
└──────────────────┴───────────────────┴─────────────────┴────────────────────┘
```

### Module Responsibilities

| Module               | Purpose                                           | Purity                       |
|----------------------|---------------------------------------------------|------------------------------|
| **Buffer**           | Gap buffer text storage with line indexing         | Pure (no I/O)                |
| **Document**         | File operations, undo/redo, VCS diff integration  | Stateful                     |
| **View**             | Viewport position, cursor, selection state        | Stateful                     |
| **Renderer**         | Converts editor state to ANSI escape sequences    | Pure function                |
| **InputParser**      | Decodes terminal input into semantic events       | Stateful (partial sequences) |
| **Terminal**         | Raw mode, screen size, clipboard, low-level I/O   | Side effects                 |
| **Theme**            | Color definitions for UI elements                 | Pure data                    |
| **Preferences**      | User settings with change callbacks               | Stateful                     |
| **Editor**           | Main loop, key bindings, orchestration            | Stateful                     |
| **CommandRegistry**  | Command table, shortcuts, palette filtering       | Pure data + functions        |
| **FindEngine**       | Incremental search with background processing     | Stateful                     |
| **Highlighter**      | Syntax detection, line-level token caching        | Stateful                     |
| **FileTree**         | File explorer tree model with VCS status          | Stateful                     |
| **FileSearchEngine** | Cross-file search via external tools              | Stateful (async I/O)         |
| **Diff**             | Myers diff algorithm for VCS gutter               | Pure function                |
| **InputWidget**      | Text input for find bar, palette, footer          | Stateful                     |
| **WrapMap**          | Word wrap computation, visual row mapping         | Pure function                |
| **LineMap**          | Maps display rows to document lines (diff view)   | Pure function                |
| **Minimap**          | Braille-based scrollbar/minimap computation       | Pure function                |
| **Chars**            | Nerd Font / ASCII glyph abstraction               | Pure data                    |
| **TabManager**       | Multi-tab state, ordering, MRU tracking           | Stateful                     |
| **FilePicker**       | Fuzzy file finder with incremental scoring        | Stateful                     |
| **Config**           | Global configuration constants                    | Pure data                    |

### Data Flow

```
  Keyboard/Mouse                                              Screen
       │                                                         ▲
       ▼                                                         │
  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ Terminal │───▶│  Input  │───▶│ Editor  │───▶│Renderer │───▶│Terminal │
  │  (read)  │    │ Parser  │    │         │    │         │    │ (write) │
  └──────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
                                      │
                 ┌────────────────┬────┴────┬────────────────┐
                 ▼                ▼         ▼                ▼
           ┌──────────┐   ┌──────────┐ ┌────────┐   ┌────────────┐
           │   View   │   │ Document │ │FileTree│   │ FindEngine │
           └──────────┘   └──────────┘ └────────┘   └────────────┘
                                │
                          ┌─────┴─────┐
                          ▼           ▼
                    ┌──────────┐ ┌────────┐
                    │  Buffer  │ │  Diff  │
                    └──────────┘ └────────┘
```

## The Gap Buffer

The gap buffer is the core data structure for text storage. It enables O(1) insertions and
deletions at the cursor position—exactly where edits happen most often.

### Concept

A gap buffer is an array with a "gap" (unused space) at the cursor position:

```
Text content: "Hello World"
Cursor position: after "Hello "

┌───┬───┬───┬───┬───┬───┬ ─ ─ ─ ─ ─ ┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │   │    GAP    │ W │ o │ r │ l │ d │
└───┴───┴───┴───┴───┴───┴ ─ ─ ─ ─ ─ ┴───┴───┴───┴───┴───┘
                        ▲
                     cursor
```

### Operations

**Insert at cursor** — O(1): Just place characters in the gap.

```
Insert "Beautiful ":

Before: [H][e][l][l][o][ ][ GAP ][ ][ ][ ][ ][ ][W][o][r][l][d]
After:  [H][e][l][l][o][ ][B][e][a][u][t][i][f][u][l][ ][ GAP ][W][o][r][l][d]
```

**Delete at cursor** — O(1): Expand the gap over deleted characters.

**Move cursor** — O(n): Shift characters across the gap. But cursor movement is usually local
(next character, next line), so amortized cost is low.

### Implementation

We use two strings instead of a literal array with gap:

```perl
{
    pre_gap  => "Hello ",      # Text before cursor
    post_gap => "World",       # Text after cursor
}
```

The "gap" is implicit—it's the boundary between the two strings.

**Insert:** Append to `pre_gap`
**Delete:** Remove from start of `post_gap`
**Move left:** Transfer from end of `pre_gap` to start of `post_gap`
**Move right:** Transfer from start of `post_gap` to end of `pre_gap`

### Why Not Just a String?

Perl strings support insertion, but it's O(n)—every insert copies the entire tail:

```
"Hello World"  →  insert "X" at position 5  →  "HelloX World"
                  Copies " World" (6 chars)

For a 10MB file, every keystroke copies megabytes.
```

With a gap buffer, inserting at the cursor copies nothing.

### Line Index

For line-based operations (go to line N, get line content), we maintain an index:

```perl
# "Hello\nWorld\n"
_line_index => [
    [0, 6],   # Line 0: starts at offset 0, length 6 ("Hello\n")
    [6, 6],   # Line 1: starts at offset 6, length 6 ("World\n")
]
```

The index is rebuilt lazily after edits. This gives O(1) line lookups.

## UX Principles

### No Modes

Vim's modal editing is powerful but has a learning curve. Zepto is modeless:
- Characters always insert
- Ctrl/Alt combinations trigger commands
- What you see is what you get

### Discoverable Interface

Every feature is findable without reading documentation:

1. **Menu bar** — Always visible, shows all commands
2. **Keyboard shortcuts in menus** — Learn as you use
3. **Status bar hints** — Shows context-relevant help
4. **Standard conventions** — Ctrl+S saves, Ctrl+Z undoes, Ctrl+Q quits

A new user should be productive in under 30 seconds.

### Mouse First, Keyboard Deep

- Mouse works for everything (click, drag, scroll, menus)
- Keyboard shortcuts exist for power users
- Both are first-class citizens

### Minimal Friction

- Opens instantly
- No config file required (or supported)
- Sensible defaults
- Quit works (double-tap if unsaved changes)

## Rendering Strategy

### Double Buffering

We build the entire screen in memory, then write it in one `syswrite()` call:

```perl
$terminal->hide_cursor();
$terminal->buffer($content);   # Build in memory
$terminal->flush();            # Single write
$terminal->show_cursor();
```

This eliminates flicker from partial updates.

### ANSI Escape Sequences

Modern terminals support:
- 24-bit RGB color: `\x1b[38;2;R;G;Bm` (foreground), `\x1b[48;2;R;G;Bm` (background)
- Cursor positioning: `\x1b[row;colH`
- Screen clearing: `\x1b[2J`
- Mouse tracking: `\x1b[?1002h` (button events), `\x1b[?1006h` (SGR extended)

We use RGB colors for rich theming while remaining compatible with any modern terminal emulator.

### Semantic Colors

Themes define colors by role, not by value:

```perl
{
    fg           => fg_rgb(212, 212, 212),  # Main text
    bg           => bg_rgb(30, 30, 46),     # Background
    selection_bg => bg_rgb(68, 68, 102),    # Selected text
    menu_fg      => fg_rgb(200, 200, 220),  # Menu text
    error_fg     => fg_rgb(255, 100, 100),  # Error messages
    ...
}
```

This allows consistent theming—change the theme, and every UI element updates coherently.

## Testing Strategy

See `docs/CODE_QUALITY.md` for testing standards, test categories, and patterns.

The key architectural enabler: keeping Renderer pure (state in → string out) means rendering can
be tested without a terminal. `make test` runs the full suite; `make check` verifies Perl syntax.

## Build System

### Single-File Bundling

Development uses separate module files for maintainability. The build script concatenates them:

```bash
make build  # Creates ./zepto
```

The build process:
1. Reads each module file
2. Strips `use Zepto::*` lines (they're now inline)
3. Concatenates with section headers
4. Adds shebang and runner code

### Why Not Use a Perl Bundler?

Tools like PAR or FatPacker add complexity and dependencies. Our build.pl is 50 lines of simple
string manipulation. It does exactly what we need and nothing more.
