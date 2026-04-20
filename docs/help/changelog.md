# Changelog

## 2026-04-20

- Added KDL syntax highlighting (.kdl files)

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
