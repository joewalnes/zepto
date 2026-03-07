# Features

## Editing

- **Undo / Redo** with automatic edit grouping
- **System clipboard** integration (macOS, X11, Wayland)
- **Cut/Copy with no selection** operates on the current line
- **Move lines** up/down
- **Duplicate lines** up/down
- **Toggle comment** -- language-aware for all 52 supported languages, including embedded languages (JS/CSS inside HTML)
- **Auto-indent** on Enter
- **Indent/Unindent** selection with Tab/Shift+Tab
- **Column (rectangular) selection** with columnar cut/copy/paste
- **Transform via Shell** -- pipe any selection through an arbitrary shell command

## Search & Replace

- **Incremental search** with real-time match highlighting
- **Viewport-first search** -- visible matches appear instantly; full-document search runs in the background without blocking typing
- **Regex support** with up to 4 capture groups highlighted in distinct colors
- **Case-sensitive** and **regex** toggles
- **Replace one** or **Replace all** with live preview before committing
- **Match count** display with keyboard and mouse navigation between matches
- **Find in Files** -- cross-file search using `git grep`, `rg`, or `grep` with grouped results in the command palette

## Navigation

- **Go to Line** -- supports `line`, `line:col`, and `:col` formats
- **Smart Home** -- alternates between column 0 and first non-whitespace
- **Word movement** with Alt+Arrow keys
- **Location history** -- go back/forward across files, like an IDE
- **VCS change navigation** -- jump between git hunks

## File Management

- **Fuzzy file picker** -- search all project files, auto-skips noise directories
- **Recent files** -- persisted across sessions
- **Atomic saves** -- writes to temp file then renames, preventing data corruption
- **Line ending detection** -- auto-detects and preserves LF vs CRLF
- **External change detection** -- notices when files are modified outside the editor

## Tabs

- Full tab bar with click, drag-to-reorder, close buttons, and scroll arrows
- Switch tabs by number, keyboard, or mouse
- Modified indicator and git status tinting on tab labels
- Unsaved-changes prompt on close (Save / Discard / Cancel)

## Syntax Highlighting -- 52 Languages

C, C++, C#, Clojure, CMake, Crontab, CSS, Diff, Dockerfile, Fish, Go, GraphQL, Groovy, HTML, INI, Java, JavaScript/JSX, JSON, Kotlin, LaTeX, Logfile, Lua, Makefile, Markdown, Nginx, Nix, Objective-C, Perl, PHP, Properties, Protobuf, Python, R, ReStructuredText, Ruby, Rust, Scala, SCSS, Shell, SQL, SSHConfig, Swift, Systemd, Terraform/HCL, Thrift, TOML, TypeScript/TSX, XML, YAML, Zig

- Handles multi-line constructs (strings, comments, heredocs)
- Incremental re-highlighting from the edited line forward
- Embedded language support (JS and CSS inside HTML)

## Git Integration

- **Gutter indicators** -- green (added), yellow (modified), red triangle (deleted)
- **Inline diff view** -- expand hunks inline with character-level highlighting
- **Diff summary** in the status bar
- **VCS status in file tree** -- color-coded modified/added/untracked/staged/ignored files

## File Tree

- Toggleable side panel with lazy-loaded directory tree
- Natural sort ("file2" before "file10")
- Keyboard navigation, mouse click/scroll/drag-resize
- Preview files by navigating the tree
- Sticky parent headers while scrolling
- Auto-reveals current file when switching tabs

## Command Palette

- Every feature searchable by name or shortcut
- Organized sections (File, Edit, Navigate, View, Diagnostics)
- Shows toggle states, icons, and keyboard shortcuts
- Mouse-clickable; typing a shortcut while open executes it directly

## Minimap

- Braille-character density map showing text structure
- VCS indicator column
- Viewport highlight showing visible region
- Click to jump, drag to scroll

## Appearance

- **Dark** (Tokyo Night inspired) and **Light** themes, toggle at runtime
- **True-color** (24-bit RGB)
- **Nerd Font support** with full ASCII fallback
- **Word wrap** per-tab with filetype-aware defaults

## Mouse Support

- Click to position cursor, click+drag to select, Alt+drag for column selection
- Scroll wheel for smooth viewport scrolling
- Full mouse interaction on tab bar, status bar, file tree, minimap, and find bar
- Drag to resize file tree panel

## Performance & Reliability

- Viewport-first rendering for search and highlighting
- Built-in performance profiler (20 slowest frames with subsystem breakdown)
- Structured crash reports with editor state and stack trace
- Alternate screen buffer (doesn't clobber terminal scrollback)
- Clean terminal restoration even on crash
