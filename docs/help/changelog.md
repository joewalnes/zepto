# Changelog

## 2026-09-01

- Fixed the cursor being left outside the document's valid line numbers after undoing a pasted block of text. Previously, pasting several lines and then pressing Undo could leave the position indicator pointing at a line that no longer existed (e.g. "6:1" in a 3-line file) — and the next character you typed was silently inserted somewhere other than where the cursor appeared, so text ended up in the wrong place with no warning. The cursor now always stays within the document after any Undo or Redo
- Fixed a hardcoded developer-machine path (`/Users/joe/src/zepto`) in the QA test catalog's installation/CLI and preferences documentation that could confuse anyone else copy-pasting the example commands on their own machine or in CI. No behavior change — internal QA docs only
- Fixed Cut (⌃X) and Copy (⌃C) freezing the whole editor if the system clipboard command hangs (e.g. a wedged `pbcopy`/`xclip`/`wl-copy`, or one blocked writing to a slow/stuck consumer) — previously there was no timeout at all on this path, unlike paste which was already fixed the same way. A hang is now detected within a few seconds and shows "Cut: system clipboard write timed out" / "Copy: system clipboard write timed out" instead of freezing; the cut/copy itself still completes normally within the editor either way, only the system clipboard sync can fail
- Fixed Perl warnings (e.g. typing an ordinary incomplete regex quantifier like `(a?){` into the find bar in regex mode) corrupting the screen with raw warning text scrolled across the document area. Warnings are now redirected to a `warnings.log` file next to your preferences instead of hitting the terminal directly — nothing is silently lost, it's just off the live display
- Fixed Replace All requiring a separate Undo press per replacement instead of one Undo for the whole operation, when replacing 100 or fewer matches (the common case) — pressing Undo once now reverts every replacement at once, matching what already happened for very large (100+) match counts. Redo works the same way in reverse
- Fixed a rendering glitch that could show newly-replaced text truncated to the length of the old text it replaced (only reachable via the Replace All fix above, and now closed alongside it)
- Fixed scrolling to the end of a file with the mouse wheel: the last line used to be able to scroll all the way to the top of the screen, leaving the rest of the window blank underneath it. It now stops with the last line pinned at the bottom of the screen, like most editors. Scrolling with the arrow keys was never affected by this

## 2026-08-31

- Status bar pills now each show their own `⌃`/`⌥` modifier glyph (e.g. `Save ⌃S`, `Word Wrap ⌥Z`) instead of showing the modifier once as a shared column header — the shared header was easy to miss when scanning a single pill in isolation. This also frees up space previously spent on the header, so pills stay in their full labeled form at narrower terminal widths than before
- Fixed `⌃B` hiding the file tree instead of switching focus back to it when the tree was open but not focused (e.g. right after opening a file from the tree, clicking into the document, or pressing Esc to return to the editor). `⌃B` now correctly refocuses the tree from that state — it still shows+focuses the tree when hidden, and still hides it when pressed a second time while the tree is already focused
- Added file tree filtering: press `/` while the tree is focused to type-to-filter across every file in the project — matching files appear in a flat list with the matched characters highlighted, and Enter opens the highlighted result. Backspace edits the search; Escape clears the search first, then a second Escape returns focus to the editor. A "/ filter" hint now appears in the tree's status bar so this is discoverable without reading any documentation
- Fixed completion suggestions (ghost text) rendering in the wrong place when the cursor wasn't at the end of the line — previously the suggestion always appeared after the line's real content, which looked confusingly garbled whenever the cursor was mid-line with other text after it (e.g. after undo/redo, or navigating back into a word). Suggestions now always appear right at the cursor. The common case — typing normally, cursor at the end of the line — is unaffected. Accepting a suggestion (Tab) still inserts it correctly either way
- The find bar now shows which replace mode is active: the label next to the replace field reads "Rep All:" or "Rep One:" (colored like the regex/case toggle buttons) instead of a plain "Replace:" that looked the same either way. Previously there was no way to tell which mode you were in, or that Shift+Tab even toggled it, without reading the source code. Click the label to switch modes directly, or use the new "Replace All Mode" command in the command palette — Shift+Tab still works exactly as before
- Fixed the status bar shifting slightly whenever you switched between Light and Dark theme — the word "light" is one character longer than "dark", which used to nudge every pill after the Theme indicator over by a column, and at some terminal widths could even make the "Word Wrap" label disappear in one theme but not the other. Both themes now render at exactly the same width
- Fixed the find/replace bar sometimes displaying the Find or Replace field's text one character short right after pressing Shift+Tab (e.g. typing "aaa" would briefly display as "aa"). The typed text itself was always intact — this was purely a display glitch caused by the field's on-screen width narrowing for a single frame while the search was mid-refresh. Also fixes the same class of glitch anywhere else a status-bar text field (Go To Line, Save As, the command palette filter) could in principle be affected by a similarly-timed width change

## 2026-08-30

- Fixed a real data-corruption bug in multi-cursor and column-select editing: backspacing across a line-join, or deleting a multi-line selection, while a second cursor was active could leave that other cursor pointing at the wrong place in the document (or at a line number that no longer existed) — the very next keystroke would then silently insert or delete in the wrong spot. Multi-cursor and column-select editing that stays within a single line was never affected
- Improved Find in Files robustness: an unusual regex pattern can no longer make a project-wide search hang indefinitely — matching is now time-bounded the same way in-buffer regex find/replace already was. A pathological pattern now just skips the one line it couldn't finish checking in time and the search continues normally, instead of freezing
- Fixed tab-character rendering re-computing every visible line from scratch on every keystroke, scroll, or cursor move, instead of reusing work for lines that didn't actually change. Rendering is unaffected (tab-indented lines and Tab Width changes still display exactly as before) — this is a speed-only fix, most noticeable when typing in large, heavily tab-indented files
- Fixed a preference-sync check re-running far more often than intended (documented as roughly once a second, actually running on every single keystroke). Cross-instance preference sync (e.g. changing Tab Width in one open window and seeing it in another) still works exactly the same, just checked at its originally intended interval instead of continuously — this is a speed-only fix
- Fixed syntax highlighting re-computing every visible line from scratch on every keystroke, scroll, or cursor move, instead of reusing work for lines that didn't actually change. Highlighting itself is unaffected (multi-line comments/strings still re-highlight correctly the moment an earlier line changes what they should look like) — this is a speed-only fix, most noticeable when typing in large files with syntax highlighting on

- The file tree's status bar now shows a "⌃B back" hint for switching focus back to the editor (the tree stays open — this is different from Esc, which closes it) — previously there was no on-screen hint for this anywhere while the tree was focused. When there's enough room, the tree's status bar also shows the same close-tab/switch-tabs/quit hint the editor's tab bar shows
- Fixed the file tree's status bar overflowing and corrupting the screen at narrow terminal widths when the selected file/folder's path was more than a few characters long — the path now shortens with an ellipsis instead of pushing the row off-screen
- Improved the tab bar's readability: inactive tabs previously had no background fill at all (just underlined text blending into the toolbar) — active, inactive, and hover states now each have their own clearly distinguishable background color in both themes, so every tab reads as a distinct, bounded element
- Quit (⌃Q) now has an always-visible on-screen hint in the tab bar, the same as close/next/prev-tab already did — previously it had no on-screen hint anywhere at all
- The tab bar's close/tab-nav/quit hint now shows plain-language labels ("close", "tabs", "quit") next to the shortcut glyphs when there's room, instead of raw glyphs alone — falls back to the compact glyphs-only form at narrower widths
- Fixed the light-theme "unsaved changes" tab icon being nearly invisible (was ~1.2:1 contrast, now clears WCAG 3:1)
- Added an automated contrast check (`make test`) covering every color pair in both themes, to catch this kind of readability bug before it ships
- Fixed file-tree preview failing silently (e.g. a file's permissions change after it's listed in the tree) — an error message now appears in the status bar instead of nothing happening
- Fixed preference-toggle confirmations (Auto Pairs, Mouse, Search Wrap Around, etc.) occasionally rendering in error (red) styling instead of normal styling if they appeared right after an error message
- Improved search robustness: an unusual regex pattern (in regex-find or replace) can no longer make the editor stop responding — matching is now time-bounded the same way regex compilation already was
- Fixed a periodic per-edit slowdown in word wrap: editing a line that gains or loses a wrapped visual row, near the top of a large wrapped file, used to briefly re-scan every line below it. Wrapped display is unaffected — this is a speed-only fix, verified with the full existing word-wrap test/QA coverage plus new correctness checks
- Improved color contrast across dozens of UI elements in both themes: gutter and ruler line numbers, tab close/shortcut/VCS icons, the file tree panel (borders, indent guides, scrollbar), the command palette's selected-row text, completion dropdown borders and ghost text, the minimap, table borders, the word-wrap indicator, and status bar warning/position colors — all previously fell short of the WCAG 3:1 minimum for UI elements and are now fixed, with no more known contrast debt in either theme
- Fixed editing/scrolling large files getting slower the bigger the file gets: reading a single line no longer re-copies the entire document (was happening 40-80x per rendered frame), and most single-character typing/backspacing no longer triggers a full-document rescan of the line index. Typing-and-rendering on a 30,000-line file is now roughly 19x faster; reading a line while scrolling is roughly 34x faster
- Fixed typing at the front of an existing word (e.g. jumping to a line and typing a prefix) sometimes showing a stale, duplicated copy of that word's own trailing text on screen — was never a data-correctness issue (saved files were always correct), just a confused word-completion suggestion offering to "complete" text that was already there
- Fixed ⌃Space (open command palette) sometimes doing nothing at all when the cursor sat right after a single typed character — it now always opens the palette (or the completion menu, when a real completion is actually available)
- Fixed typing a space right after pressing Escape (e.g. to dismiss ghost-text suggestions) occasionally dropping that space, gluing the new text onto the previous word with no separator
- The minimap now automatically hides itself below 60 columns wide — at 40 columns it was barely legible anyway and was crowding out document content and status bar space that matters more. The manual Minimap toggle (⌥M) is unaffected above that width
- Fixed a real screen-corruption bug: with multi-cursor mode or column-select mode active at a narrow terminal width, the status bar could overflow past the terminal's column count, causing the terminal itself to scroll and lose the tab bar/ruler from view. The status bar's supplementary indicators (cursor count, column-selection size) now drop gracefully instead of overflowing — the cursor position and "Commands" pills always stay visible
- Fixed the blank rows reserved below an inline Markdown image (Kitty-graphics-capable terminals) sometimes showing the wrong background color instead of the current theme's real background
- Fixed Ctrl+Enter, Ctrl+Tab, Ctrl+Backspace, and Ctrl+Escape being silently dropped on terminals that use the Kitty keyboard protocol (e.g. Kitty, WezTerm, Ghostty) — these modified special keys previously did nothing at all; they now register correctly
- Fixed "Tab Width" only affecting newly-typed indentation — it now also affects how a file's existing tab characters are displayed and wrapped. Changing it in the palette re-renders any already-open tab-indented file immediately
- Paste (⌃V) no longer freezes the editor indefinitely if the system clipboard command hangs — it now times out after a few seconds and shows an error message instead
- Fixed Find & Replace's live preview: typing in the replace field could leave stacked, uncleared duplicate rows on screen (most noticeable at the common 80-column terminal width) and could show the wrong preview text (e.g. typing "XYZ" over a prefilled "foo" showed "fooXYZ" instead of replacing it, so the preview read "fooXYZ bar" instead of "XYZ bar"). The replace field's prefilled text is now selected on Tab (so typing replaces it, matching how the Find field already worked), and the find/replace bar no longer overflows the terminal width. Confirmed the preview never touched the real document or undo history in either case
- Hardened AI Completion's request handling: the API key is no longer passed on the command line to the underlying `curl` process, where it could briefly be visible to other users on a shared machine (via `ps`) for the duration of each completion request — it's now delivered through a short-lived, restricted-permission file instead
- "AI Completion: Setup" now requires the API URL to start with `https://` and shows a clear error if it doesn't, instead of silently accepting a plaintext `http://` URL that would send your API key unencrypted

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
