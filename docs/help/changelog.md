# Changelog

## 2026-08-30

- Fixed the light-theme "unsaved changes" tab icon being nearly invisible (was ~1.2:1 contrast, now clears WCAG 3:1)
- Added an automated contrast check (`make test`) covering every color pair in both themes, to catch this kind of readability bug before it ships
- Fixed file-tree preview failing silently (e.g. a file's permissions change after it's listed in the tree) — an error message now appears in the status bar instead of nothing happening
- Fixed preference-toggle confirmations (Auto Pairs, Mouse, Search Wrap Around, etc.) occasionally rendering in error (red) styling instead of normal styling if they appeared right after an error message
- Improved search robustness: an unusual regex pattern (in regex-find or replace) can no longer make the editor stop responding — matching is now time-bounded the same way regex compilation already was
- Fixed a periodic per-edit slowdown in word wrap: editing a line that gains or loses a wrapped visual row, near the top of a large wrapped file, used to briefly re-scan every line below it. Wrapped display is unaffected — this is a speed-only fix, verified with the full existing word-wrap test/QA coverage plus new correctness checks
- Improved color contrast across dozens of UI elements in both themes: gutter and ruler line numbers, tab close/shortcut/VCS icons, the file tree panel (borders, indent guides, scrollbar), the command palette's selected-row text, completion dropdown borders and ghost text, the minimap, table borders, the word-wrap indicator, and status bar warning/position colors — all previously fell short of the WCAG 3:1 minimum for UI elements and are now fixed, with no more known contrast debt in either theme
- Fixed editing/scrolling large files getting slower the bigger the file gets: reading a single line no longer re-copies the entire document (was happening 40-80x per rendered frame), and most single-character typing/backspacing no longer triggers a full-document rescan of the line index. Typing-and-rendering on a 30,000-line file is now roughly 19x faster; reading a line while scrolling is roughly 34x faster
- Fixed ⌃Space (open command palette) sometimes doing nothing at all when the cursor sat right after a single typed character — it now always opens the palette (or the completion menu, when a real completion is actually available)
- Fixed typing a space right after pressing Escape (e.g. to dismiss ghost-text suggestions) occasionally dropping that space, gluing the new text onto the previous word with no separator

## 2026-08-29

- Status bar reworked: shortcuts are now grouped into a ⌃ (Ctrl) column and an ⌥ (Alt) column, each showing its modifier once instead of on every pill — the most useful action in each column (Save, Word Wrap) now stays visible even in a narrow terminal
- Markdown emphasis delimiters (`**`, `*`, `_`, `~~`, `==`) now render in a dimmed color so bold/italic/strikethrough/highlighted text pops out visually
- Added session restore: relaunching zepto with no file arguments now reopens the tabs, cursor positions, and scroll positions you left in that directory. Explicit file/directory args always bypass it. Toggle via "Restore Session on Startup" in the command palette (on by default)
- Added automatic dark/light theme mode: pick "Theme: Auto" from the command palette to follow the system appearance (macOS/GNOME), with a periodic check while running. Manual dark/light selection ("Theme: Dark", "Theme: Light", or ⌃T) always still works and takes an explicit choice out of auto
- Fixed a terminal response (used internally by auto theme detection) potentially typing garbage characters into the document
- Fixed the theme icon in the command palette staying a moon regardless of the current mode
- New palette commands to set/toggle preferences that had no UI before: "Tab Width" (footer prompt, 1-16), "Soft Tabs (Spaces)", "Auto Indent", "Mouse", "Search Wrap Around", "Markdown Table Rendering" — all now persist across restarts like the other preferences
- Fixed "Tab Width" (and any similarly invalid preference input) failing silently instead of showing an error message
- Added a direct keyboard shortcut for Duplicate Down: ⌥U (pairs with ⌃U for Duplicate Up)
- Added a "Save As" command to the palette (FILE section) — prompts for a path even when the document already has one, confirms before overwriting a different existing file, and activates syntax highlighting for the new extension
- Added 5 built-in text transforms to the palette (new TRANSFORM section): Uppercase, Lowercase, Sort Lines, Reverse Lines, Unique Lines — operate on the selection, or the whole document if none, no shell required. "Transform via Shell" (⌥T) is unchanged
- Fixed long status messages (e.g. "Saved: /very/long/path...") overflowing past the terminal width and scrolling/corrupting the screen — long messages are now truncated with a leading "…"
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
