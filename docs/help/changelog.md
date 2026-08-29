# Changelog

## 2026-08-29

- Added a direct keyboard shortcut for Duplicate Down: ⌥U (pairs with ⌃U for Duplicate Up)
- Fixed find bar showing an out-of-range match counter (e.g. "3 of 1") after toggling regex/case shrinks the results

## 2026-08-28 (later)

- Find now defaults to literal search — press ⌃R to enable regex matching
- Hovering a status bar pill now always brightens it (bright pills used to dim on hover)
- New `--no-system-clipboard` flag: copy/paste use only the editor's internal clipboard

## 2026-08-28

- Fixed editor appearing frozen after mouse movement — typed text and cursor moves now render immediately instead of waiting for the next click
- Fixed keystrokes lagging one event behind when the terminal sends unrecognized escape sequences

## 2026-04-23

- Fixed move-line undo corruption — Ctrl+Z after Alt+Up/Down now correctly restores line order
- Fixed file tree Page Down/Up/Home/End not updating preview

## 2026-04-20

- Added KDL syntax highlighting (.kdl files)
- Mouse hover effects on tabs, status bar pills, and file tree items
- Pretty-rendered Markdown tables with box-drawing borders, column alignment, and syntax highlighting
- Fixed screen artifacts remaining after quitting

## 2026-03-23

- Multi-cursor editing with Ctrl+D (select next occurrence)
- Fixed find mode, auto-pairs, ghost text, and UI hint bugs
- Fixed completion crash after undo

## 2026-03-22

- Homebrew formula and tabbed install UI on homepage

## 2026-03-20

- Self-installing `--install` flag and `curl|sh` installer

## 2026-03-15

- Text completion with ghost text and dropdown menu
- Cross-buffer word completion, auto-pairs, snippets, recent tracking

## 2026-03-14

- Inline image rendering with proper aspect ratio
- Fixed clipboard paste corrupting Unicode characters
- Fixed native terminal paste causing cascading indentation
- Fixed file picker not finding untracked files
- Fixed syntax highlighting not activating after Save As
- Fixed YAML highlighting inside bare words
- Fixed light mode tab bar color after theme switch
- Binary file tabs now show READ ONLY properly

## 2026-03-08

- File tree auto-expands to reveal opened files
- Large file performance improvements (O(1) VCS lookups, minimap caching)
- Fixed cursor alignment in Open File and Recent Files pickers

## 2026-03-07

- Fixed crash when copying double-width characters to clipboard
- Wide character handling improvements
- Security: symlink traversal protection, regex timeout protection
