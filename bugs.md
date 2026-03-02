# Bugs

Priority scale:
- **P0**: Broken core functionality — data loss, crash, or fundamentally wrong behavior.
- **P1**: Significant usability issue — feature works but is confusing or misleading.
- **P2**: Polish issue — inconsistency, visual glitch, or minor misbehavior.
- **P3**: Cosmetic / edge case — low impact, fix when convenient.

---

## Existing bugs

### ~~P2: Scroll wheel cannot scroll more than a page~~ FIXED
When using scroll wheel, the doc offset scrolls, but gets stuck when the selected line hits top or bottom, preventing scrolling more than a page at a time.

**Fix:** Added `_explicit_scroll` flag to View. When `scroll_up`/`scroll_down` are called (mouse wheel), the flag is set. `ensure_cursor_visible()` (called every render) checks for this flag and returns early if set, preventing the viewport from snapping back to the cursor. The flag is consumed after one render cycle, so the next user action (typing, clicking) restores normal cursor-following behavior. This allows unlimited scrolling away from the cursor position, matching standard editor behavior.

### ~~P2: "More" home/end~~ FIXED
Pressing home once on line should jump to first non-whitespace char (e.g. where code is indented). Pressing again should jump to start of actual line (in front of whitespace). Pressing one more time should jump to start of doc (line 1). Similar for End.

**Fix:** Smart Home cycles three states: first-nonws → col 0 → document start. Smart End cycles: line end → document end. Both work in normal and word-wrap modes. Also fixed `do_enter()` to set cursor position directly instead of using `move_to_line_start()` (which now has smart cycling that would send the cursor to doc start on empty new lines).

### P3: Move forward/back
Keep a history of major locations visited across files and within files. Many editors support something like this. Keyboard shortcuts to quickly move back forward throught location histor.

### P2: Recent files
Like ^O open, but list of recently visited files. Sorted by most recent first.

### ~~P0: Reports of sluggishness~~ FIXED
Some users have reported a delay between typing and seeing results on screen. Hard to reproduce. Go explore and figure out likely cause.

**Fix:** Found three per-render bottlenecks: (1) WrapMap was unconditionally invalidated and rebuilt from scratch on every render, even when content hadn't changed — added `_content_version` counter to Document so WrapMap auto-detects changes and only rebuilds when needed. (2) `head_changed()` did file I/O (open + read + stat on `.git/HEAD`) on every render — debounced to every 2 seconds. (3) `check_external_changes()` did `stat()` on the active file every render — debounced to every 1 second.

### P3: Lightmode glitches
In lightmode. On short docs, the space beyond the final line is grey and looks out of place. 

### P3: Screen width
The ruler, minimap, and bottom status bar all stop one char short of the end of the window. The tab bar does not. Ensure all reach end of window so entire screen is filled.

### P3: Status bar spacing
No space between the Line number pill (first in status bar) and word wrap, whereas all others have spaces.

### ~~P2: Go-to-line new UI~~ FIXED
The status bar starts with a line number pill, and also has a go to line pill. Collapse these into a single element.
The line number pill (first), should also sho the ^G shortcut. When pressing this key, or clicking the pill, the line:col
string should become editable. Initially the entire text should be selected, allowing user to start typing and replace selection, or to move the cursor and edit existing. User may end XX, XX:YY, or :YY to move line, line and col, or just col (on same line) respectively - there should be text hints displayed to explain this. Use standard text input component used elsewhere. Ensure this box is wide enough to support docs of at least 9999:999. Beyond that, ok to scroll.

**Fix:** Merged the separate "Go to Line" pill into the cursor position pill. The pill now shows `⌃G` shortcut and is clickable. Pressing ⌃G or clicking the pill opens an inline input pre-filled with the current `line:col` (all selected, so typing replaces). Hint text shows "line, line:col, or :col" format guide. Input is 10 chars wide (enough for 9999:999 with scrolling for larger). The "Go to Line" command remains in the command palette for discoverability.

### P3: Theme ^T should be global shortcut
For example, should work when in find dialog.

### ~~P2: Comment/uncomment line~~ FIXED
Ctrl+/ should comment or uncomment the current line. If no text selected, current line. If text selected, all lines this selection spans. Language specific comments, e.g. # or // or <!-- .. -->. For languages that support multiline comment blocks, dont use this, only single lines (e.g. yes on //, no on /* .. */). Handle cases for mixed language documents (e.g. HTML with embedded CSS or JS).

**Fix:** Added `line_comment_prefix()` to `Zepto::Syntax::Base` with a lookup table covering all 42 syntax languages. `cmd_toggle_comment` in Commands.pm detects the language from the active highlighter's grammar, determines the line range (single line or selection), checks if all non-blank lines are already commented, and toggles accordingly. Comments are aligned at the minimum indentation of the selected lines. Wired to `⌃/` (Ctrl+/) and registered in CommandRegistry under DOCUMENT section.

### P3: Close empty start tab when opening first file.
A common scenario is: open zepto (which shows an untitled empty tab), then navigate to a file to edit. In this case, if the initial empty tab has not been edited, automatically close it to reduce clutter.

### ~~P2: Line by line scrolling in editor.~~ FIXED
When using mouse scrolling (wheel or touchpad gesture), the file tree scrolls item by item, which feels precise and smooth. However the editor has different behavior which feels janky. Make editor mouse scroll behave same way as tree.

**Fix:** Changed editor mouse scroll from 3 lines per event to 1 line per event, matching the file tree's behavior.

### P3: Diff view does not preserve line wrap
If word wrap enabled, and diffing a hunk with long line, the word wrap is disabled in the diff, which is jarring. Preserve word wrap settings.

### ~~P2: Find/replace pills should be clickable~~ FIXED
Regex, case sensitivie, ok, cancel: mouse clicks should activate.

**Fix:** Already implemented — `handle_find_bar_click()` in Editor.pm computes click regions matching the renderer layout and handles clicks on all four pills: regex toggle, case toggle, cancel (Esc), and OK (Enter). Click regions are calculated from the same layout formula as the renderer to stay in sync.

### P3: Column mode mouse selection
After activating col selection mode, dragging with mouse should select col based selection, but it defaults to line.

### ~~P2: Line number indicator resizing~~ FIXED
The left pill constantly resizes as moving across lines due to empty lines (e.g. :60 -> :1). This makes the whole bar jiggle.

**Fix:** Added minimum width padding to the cursor position pill so it doesn't shrink below a reasonable size. The pill text is right-padded with spaces to keep surrounding pills stable.

### ~~P2: More prominent ctrl-space hint~~ FIXED
This is the most important key to know about, but it's hidden in corner, with no real clue as to what it means. How to make this obvious for first time users?

**Fix:** Added "Commands" label to the palette pill in the status bar. Previously showed only `{icon} ⌃␣` — now shows `{icon} Commands ⌃␣`. Updated in both document-context and tree-context status bars. The pill already uses a distinctive blue background that differentiates it from other pills.

### P3: Command palette too wide.
Doesn't need to be as wide and ends up with shortcut keys too far from respective action. Pick a reasonable max width.

### ~~P2: Non-obvious tab keys~~ FIXED
Close tab, next tab, prev tab are common actions. Succinctly display these hints somewhere, maybe in tab bar.

**Fix:** Added right-aligned tab navigation hints in the tab bar's remaining space: `⌃W × ⌥, ← ⌥. →` showing close tab, previous tab, and next tab shortcuts. Hints only appear when there's enough room, using the same dim shortcut color as the per-tab ⌥N hints.

### ~~P2: Command palette re-org~~ FIXED
Organize by:
- File: tree, new, open, save, close, quit, next/prev tab, etc
- Edit: cut, copy, paste, move line up/down, duplicate up/down
- Navigate...
- View: minimap, nerd, wrap
- etc.
Where should find/replace go

**Fix:** Reorganized command palette from DOCUMENT/APP/NAVIGATE/TOGGLES to FILE/EDIT/NAVIGATE/VIEW. FILE: New, Open, Save, Close Tab, Quit, Next/Prev Tab, File Tree. EDIT: Undo, Redo, Cut, Copy, Paste, Select All, Move/Duplicate Lines, Toggle Comment. NAVIGATE: Find/Replace, Go to Line, Find Next/Prev, Next/Prev Change. VIEW: Word Wrap, Column Mode, Diff View, Minimap, Nerd Font, Theme. Find/Replace goes in NAVIGATE (it's a search/navigation action).

### ~~P2: Command palette rendering~~ FIXED
Highlighted row in command palette extends too far on right, overlapping border.

**Fix:** Reset background to `$bg` before rendering the right border `$box_v` on each item row. The selection highlight (`$sel_bg`) was bleeding into the border character because only `$border_fg` (foreground) was set.

### P3: Nerd icon overhaul
Re-evaluate current icon selection. Many duplicates. Pick familiar feeling icons for actions.

### ~~P2: Fuzzy find text overflow~~ FIXED
Open fuzzy find with ^O and type long string - it overflows out of tree into main doc. Ensure its constrained to text box.

**Fix:** Two changes in Renderer.pm: (1) When query exceeds available width, show the tail of the string (`substr($query, -$max_query_width)`) so the cursor stays visible. (2) Cap cursor position to panel width so it doesn't escape beyond the border.

### ~~P2: Save changes prompt: more prominent~~ FIXED
Often when closign a tab, the save changes prompt appears at bottom, but it's hard to notice. Make this harder to miss, e.g. with
a intense background color. Also make yes/no/cancel into pill buttons with icons.

**Fix:** Replaced plain-text prompt with pill-style buttons on an amber/warning background. Added prompt-specific theme colors (`prompt_bg`, `prompt_fg`, `prompt_pill_*`) for both dark and light themes. Buttons now show icons: Save (floppy), Discard (✗), Cancel. Added warning icon (⚠) to Chars.pm. Updated all three prompt call sites (close tab, quit with dirty tabs, file changed on disk).

### ~~P0: New file Enter key puts cursor at beginning of current line instead of next line~~ FIXED
Create new doc, type a line of text on the last line (which for a new doc is also the first line), press Enter. Cursor jumps to beginning of current line, not next line.

**Fix:** Invalidate WrapMap after inserting newline so `move_down()` sees the updated line count. Root cause was stale WrapMap state when word wrap is active.

### ~~P0: File tree click on tab should unfocus tree and focus document~~ FIXED
When file explorer or file fuzzy find is focused, clicking on a document/tab should unfocus the tree and focus on the document.

**Fix:** Added tree unfocus + preview cleanup at the start of `handle_tab_bar_click()`. Any click on the tab bar area now returns focus to the editor.

### ~~P0: File tree preview hides for certain files~~ FIXED
When exploring files in the zepto src dir, moving cursor over `lib/Zepto/Editor.pm` and `Renderer.pm` hides the preview. Other files seem fine.

**Fix:** Used `File::Spec->rel2abs()` with the tree's root_path when checking file size for the preview limit. The `-s` operator was failing on relative paths. **Note:** Large files (>100KB) are intentionally skipped for preview — Editor.pm (111KB) and Renderer.pm (147KB) will now correctly show "no preview" instead of glitching. Manual test: navigate to these files in the tree and verify they don't cause the preview to disappear entirely.

### ~~P0: Saving one new file also saves another new file~~ FIXED
Open editor, create new file, create another new file. Save the second file with a name. The first file also seems to be saved.

**Fix:** After Save As, update the tab's `file_path` and clear `untitled_name` so the tab manager correctly tracks which file belongs to which tab. Root cause was Document getting a path but the Tab staying as untitled. **Manual test:** Create two untitled tabs, save tab 2 as "test.txt", verify tab 1 still shows as [untitled].

### ~~P0: Editor does not detect or reload externally changed files~~ FIXED
When a file open in zepto is modified outside the editor (e.g. by `git checkout`, another editor, a build script, or `save` from a second zepto instance), the buffer keeps the stale content with no indication that the disk version has changed. This leads to silent data loss: the user overwrites the newer external changes on the next save.

**Expected behavior — no local modifications (clean buffer):**
Silently reload the file from disk on the next focus/interaction. Restore the cursor to the same line and column (clamping if the file shrank). No prompt needed since there is nothing to lose.

**Expected behavior — local modifications (dirty buffer):**
Show a persistent status bar message (not time-based) such as:
`File changed on disk. [R]eload  [K]eep local  [D]iff`
- **Reload** discards local edits and loads the disk version (cursor restored best-effort).
- **Keep local** dismisses the warning and keeps the in-memory buffer. The next save overwrites the disk version.
- **Diff** opens diff view between the local buffer and the disk version so the user can decide.

The warning should reappear on every subsequent focus until the user chooses an action. It must not auto-dismiss.

**Detection:** Poll `stat()` mtime on each render cycle or input event (cheap). Compare against the mtime recorded at last load/save. No filesystem watchers needed for a minimal editor.

**Fix:** Added mtime tracking to Document (captured at load and save). On each render cycle, check if the file's mtime has changed. Clean buffers are silently reloaded with cursor restored. Dirty buffers show a prompt: `[R]eload [K]eep local`. Undo/redo stacks are cleared on reload. **Decisions:** Skipped `[D]iff` option from the original spec to keep the prompt simple — can add later. **Manual test:** Open a file, modify it externally (e.g. `echo "new" > file`), press any key in zepto — should reload silently if clean, or prompt if dirty.

### ~~P1: Diff gutter markers should extend across wrapped continuation lines~~ FIXED
When word wrap is enabled, diff gutter markers only appear on the first display row of a wrapped line. They should extend across all continuation lines.

**Fix:** Updated wrap_cont gutter rendering in Renderer.pm to check VCS change status for the underlying doc line and apply the same diff markers (added/modified/modified_whitespace). **Manual test:** Open a git-tracked file, make changes, enable word wrap — diff markers should now extend across all wrapped rows of changed lines.

### ~~P2: Mouse scroll in editor is janky compared to file tree~~ FIXED
When using mouse scroll wheel (macOS touchpad) in file tree it's buttery smooth, but in the editor it seems janky and skips lines, often gets caught in a loop.

**Fix:** Changed mouse scroll from `move_up()`/`move_down()` (cursor movement with viewport recalc) to `scroll_up(3)`/`scroll_down(3)` (viewport-only scrolling). This avoids moving the cursor and recalculating the viewport 3 times per scroll event. **Manual test:** Open a long file and scroll with the trackpad — should now be smooth, matching the file tree behavior.

### ~~P2: `^O` in fuzzy find search does not match status bar styling~~ FIXED
The `^O` label in the fuzzy file search does not match the visual styling of status bar pills.

**Fix:** Replaced all caret notation (`^O`, `^R`, `^C`) with compact glyph notation (`⌃O`, `⌃R`, `⌃C`) using `SYM_CTRL` constant from CommandRegistry. Updated in Renderer.pm for the file tree header, Find bar regex toggle, and Find bar case toggle.

### ~~P2: Don't show diff gutter markers in new files~~ FIXED
New untitled files show diff gutter markers even though there is no baseline to diff against.

**Fix:** In `_compute_vcs_diff()`, return early with `_vcs_diff = undef` when `_vcs_base` is undefined or empty. New untitled files have no VCS base content, so the diff computation is skipped entirely. **Manual test:** Create a new file (⌃N), type some text — no diff gutter markers should appear.

### ~~P3: Column selection should skip continuation lines when word wrap is enabled~~ FIXED
When word wrap and column selection are both enabled, column selection should skip over continuation lines (both mouse and arrow-based selections).

**Fix:** Updated `do_column_select_up/down` in Editor.pm to move by document line instead of visual row. Updated Renderer.pm `_render_line_with_highlights` to accept an `$is_wrap_cont` parameter — column selection rendering now skips wrap continuation rows entirely. **Manual test:** Enable word wrap (⌥Z) on a long file, enter column select mode (⌥C), use ⌥↓/⌥↑ — selection should skip continuation lines and select from real document lines only.

---

## UI guideline audit bugs

Bugs found by auditing the running UI against `docs/UI_GUIDELINES.md`.

### ~~P1: Time-based temporary messages violate "no time-based messages" rule~~ FIXED
**Guideline**: "No time-based temporary messages. Messages persist until user dismisses them or they are replaced by a newer message."

Multiple status bar messages disappear after ~3 seconds with no user interaction:
- "No change at cursor" (from Diff View toggle when no git changes)
- "Nothing to undo" (from Ctrl+Z when undo stack is empty)
- "Saved: README.md" (from Ctrl+S after successful save)

These should persist until dismissed by the user or replaced by a newer message.

**Fix:** Removed MESSAGE_DISPLAY_SEC timer. Messages now persist until the next user input clears them or a new message replaces them. **Decision:** Messages clear on any user input (keystroke or mouse) so the status bar returns to normal once the user takes any action.

### ~~P1: Esc does not open command palette as final fallback~~ FIXED
**Guideline**: "Esc priority: close palette, exit column mode, clear selection, collapse diff, open command palette (final fallback when nothing to cancel)."

When nothing is open (no palette, no selection, no column mode, no diff), pressing Esc does nothing. It should open the command palette as the documented last-resort fallback.

**Fix:** Added `cmd_open_palette()` call as the else-branch in the Escape key handler. Esc priority is now: exit column mode → clear selection → collapse diff → open command palette.

### ~~P2: Inconsistent shortcut notation — `^O`/`^R`/`^C` vs `⌃O`/`⌃R`/`⌃C`~~ FIXED
**Guideline**: "Use compact, single-glyph modifiers in UI labels: `⌃` for Ctrl, `⌥` for Alt, `⇧` for Shift, `␣` for Space. Use the same label format everywhere."

The tab bar shows `^O` (caret notation) instead of `⌃O`. The Find bar shows `^R` and `^C` instead of `⌃R` and `⌃C`. The status bar and command palette correctly use `⌃` notation. These should all use the same compact glyph format.

**Fix:** See "`^O` in fuzzy find search" fix above — same change covers all instances.

### ~~P2: Powerline toggle has no keyboard shortcut~~ FIXED
**Guideline**: "Every command has: a Nerd Font icon, a shortcut label, and a human-readable label."

In the command palette, "Powerline" shows `[on]` with no keyboard shortcut. Every other toggle (Theme, Minimap, File Tree, Word Wrap, Column Mode, Diff View) has a shortcut. Powerline is only accessible via the command palette with mouse or arrow navigation.

**Fix:** Added `⌥I` as the keyboard shortcut for Powerline toggle. Registered in CommandRegistry.pm (`shortcut => SYM_ALT . 'I'`) and handled in Editor.pm `handle_alt_char`. **Manual test:** Press ⌥I — should toggle Powerline on/off. Command palette should show `⌥I` next to Powerline.

### ~~P2: Command palette has no section headers~~ FIXED
**Guideline**: "Sections group commands in the palette: DOCUMENT, APP, NAVIGATE, TOGGLES."

The palette displays a flat list of 30 commands with no visible section headings or separators. Commands are loosely grouped by category but there are no "DOCUMENT", "APP", "NAVIGATE", or "TOGGLES" labels. This hurts scannability for users looking for a specific category.

**Fix:** When no filter query is active, section header rows are injected into the palette list (DOCUMENT, APP, NAVIGATE, TOGGLES). Headers render as dimmed label with horizontal rule fill. Arrow navigation skips headers automatically. Headers are removed when the user types a filter query (fuzzy matching only returns commands). **Manual test:** Open palette (⌃␣) — should see section headings. Type a letter — headers disappear. Backspace to clear — headers return.

### ~~P2: Minimap does not drop off at narrow terminal widths~~ FIXED
**Guideline**: "Layout adapts to constrained sizes using priority-based progressive disclosure: lower-priority status bar pills drop off first, then minimap, then file tree."

At 25 columns the minimap is still visible and consumes roughly half the editor area. The file tree drops off correctly, but the minimap persists at all widths. Per the guideline, minimap should disappear before the file tree.

**Fix:** Reversed the priority order in the layout calculation: tree width is now computed first (has priority to stay visible), minimap is computed second using remaining space. The minimap now correctly drops before the file tree at narrow widths. Updated in both Renderer.pm `render()` and Editor.pm word wrap width calculation. `get_minimap_width()` now accepts an optional `tree_width` parameter. **Manual test:** Open zepto, toggle file tree on, shrink terminal width — minimap should disappear first, then file tree.

### ~~P2: File tree status bar hints are plain text, not pills~~ FIXED
**Guideline**: "The status bar shows context-specific interactive pills. Every pill has: a Nerd Font icon, a label or value, a key shortcut — and is clickable."

When the file tree is focused the status bar shows plain text hints (`↑↓ nav  ←→ fold  Enter open  / filter  Esc back`) instead of styled pills with icons, rounded shape, and consistent padding. This is a different visual treatment from the DOCUMENT-mode status bar.

**Fix:** Replaced the plain text hint string with styled pills using the same rendering pattern as the document-context status bar. Each hint (↑↓, ←→ fold, ↵ open, / filter, Esc back) is now a separate pill with background color, rounded caps, and consistent padding. Pills drop off progressively if the terminal is too narrow. **Manual test:** Focus the file tree (⌃B) — status bar should show styled pills instead of plain text.

### ~~P2: `⌃⇧↑`/`⌃⇧↓` (Duplicate Up/Down) uses Shift for non-selection purpose~~ FIXED
**Guideline**: "Shift is only used with navigation keys to extend selection or reverse direction."

Duplicate Up (`⌃⇧↑`) and Duplicate Down (`⌃⇧↓`) use Shift+arrow to duplicate lines, not to extend a selection or reverse a direction. This contradicts the documented Shift modifier policy.

**Fix:** Changed duplicate line shortcuts to `⌃U` (duplicate up) and `⌃D` (duplicate down). Removed the `Ctrl+Shift+Arrow` bindings. Updated CommandRegistry.pm shortcut labels and Editor.pm keybindings. **Decision:** Chose `⌃U`/`⌃D` as mnemonic (U=up, D=down) and consistent with Ctrl+letter pattern. **Manual test:** Place cursor on a line, press ⌃D — should duplicate the line below. Press ⌃U — should duplicate above.

### ~~P3: Command palette does not use multi-column layout at wide terminals~~ FIXED
**Guideline**: "The palette adapts its layout (multi-column vs single-column) based on terminal width."

At 160 columns the palette remains single-column with the same width as at 100 columns. No multi-column layout is ever triggered.

**Fix:** Made palette width adaptive based on terminal width: 60 cols (standard), 80 cols at 120+ terminal width, 120 cols at 160+. Full multi-column layout was avoided as the 2D cursor navigation complexity outweighs the benefit. **Decision:** Single-column with wider box is simpler and still provides better use of space. **Manual test:** Open command palette at different terminal widths — palette should be wider at wider terminals.

---

## Open bugs

### ~~P2: Unified input widget missing~~ FIXED

Find bar, Go To Line, Save As prompt, and command palette filter are separate input implementations with inconsistent editing semantics. They should share a common input widget supporting: left/right, word left/right, home/end, select all, selection with Shift, cut/copy/paste, mouse click to place cursor.

**Guideline**: `docs/UI_GUIDELINES.md` → Inputs And Text Editing.

**Fix:** Created `Zepto::InputWidget` — a shared text input widget with full editing semantics. All three input surfaces (footer input / Go To Line / Save As, Find/Replace bar, command palette filter) now delegate to this widget. New features added to all inputs: Alt+Left/Right word movement, Shift+arrow/home/end selection, Ctrl+A select all, Ctrl+X cut, Ctrl+V paste (find bar keeps Ctrl+C as "toggle case" per its context-specific shortcut). Visual selection highlight is functional at the state level; selection-aware editing (replace-on-type, backspace/delete selection) works in all inputs. **Decision:** Mouse click cursor placement within input fields left as a P3 item (tracked separately). **Manual test:** Open find bar (⌃F), type "hello world", press Alt+Left — cursor should jump to "world". Press Ctrl+A — selects all. Open Go to Line (⌃G), type text, use Home/End/word movement — all consistent.

### ~~P2: Global navigation keys not audited across all UI states~~ FIXED

Core shortcuts (⌃Q, ⌃S, Esc) may not work from every UI state (dialogs, prompts, find mode, file tree, palette). An audit is needed to verify each one works from every surface.

**Guideline**: `docs/UI_GUIDELINES.md` → Navigation And Focus: "Core global shortcuts work in every UI state."

**Fix:** Added early interception in `handle_event()` — ⌃Q and ⌃S are now caught before routing to any state-specific handler, so they work in PALETTE, PROMPT, FOOTER_INPUT, FIND, and DIALOG states. Also removed the Esc-opens-palette fallback per user request (was triggering accidentally). **Manual test:** Open find bar (⌃F), press ⌃Q — quits. Open command palette (⌃␣), press ⌃Q — quits.

### P3: Mouse parity incomplete

Double-click word selection, triple-click line selection, and mouse cursor placement inside input fields (find/replace, go to line) are not implemented.

**Guideline**: `docs/UI_GUIDELINES.md` → Mouse And Keyboard Behavior.

### ~~P3: Light theme `status_accent` used `bg_rgb` instead of `fg_rgb`~~ FIXED

`status_accent` in the light theme was defined with `bg_rgb(30, 102, 245)` — a background color escape sequence — when it is semantically a foreground accent color (consistent with the dark theme's `fg_rgb(125, 207, 255)`). Any future use of this color for text rendering would have produced an invisible or incorrectly styled result.

**Fix:** Changed to `fg_rgb(30, 102, 245)`. Added a regression test to `tests/theme.t` asserting that `status_accent` produces a foreground escape sequence (`ESC[38;2;...`) in the light theme.

### P3: Theme contrast not verified

Dark and light themes have not been formally audited for readability or contrast. Non-color cues (icons, text) for state changes (VCS markers, selection, errors) should be verified in both modes.

**Guideline**: `docs/UI_GUIDELINES.md` → Colors And Readability.

### ~~P1: Shift+Alt+Left/Right should select by word, not column select~~ FIXED
Alt+Left/Right moves by word. The expected behavior for Shift+Alt+Left/Right is word movement with selection (standard across most editors). Instead, it triggers column selection mode. Column selection needs an alternative keybinding.

**Fix:** Removed all modifier-combo triggers for column selection from arrow handling. Column selection now works exclusively through toggle: press `⌥C` to enter column mode, then plain arrows extend the rectangular selection. Press `⌥C` or `Esc` to exit. In normal mode, arrows behave as standard: bare arrows move cursor, `Shift+Arrow` extends selection, `Alt+Left/Right` moves by word, `Shift+Alt+Left/Right` selects by word, `Alt+Up/Down` moves line. Also fixed a latent bug in `View::enter_column_mode` where `clear_selection()` was resetting `column_select` back to 0 (reordered so the flag is set after the clear). **Manual test:** `⌥C` then arrows → column rect selection shown in status bar as `COL RxC`. `Shift+Alt+Right` without column mode → word selection. `Esc` from column mode → exits column mode.

### ~~P3: Add Shift+Ctrl+D for duplicate line up~~ WON'T FIX
Ctrl+D duplicates the current line down. Shift+Ctrl+D should duplicate the line up — easy to remember since Shift is the "reverse direction" modifier.

**Resolution:** Terminals cannot distinguish `Ctrl+D` from `Ctrl+Shift+D` — both send byte `0x04`. This is documented in `docs/UI_GUIDELINES.md`: "Do not depend on `Shift+letter` or `Ctrl+Shift+letter`." Duplicate-up already exists as `⌃U` (mnemonic: U=up) paired with `⌃D` (D=down). Both are visible in the command palette under DOCUMENT section.

---

## UI guideline audit bugs

### ~~P3: Rename "Powerline" to "Nerd Font" throughout the codebase~~ FIXED
The feature that toggles Nerd Font glyph rendering is called "Powerline" everywhere — command palette label, preference key, variable names, CLI flags, comments, docs, and tests. The correct term is "Nerd Font" (Powerline refers specifically to the status line plugin whose glyph range is a small subset of Nerd Fonts). Occurrences span:
- **UI-visible**: command palette label (`Powerline`), `README.md` references, `UI_GUIDELINES.md`, `website/src/index.html`
- **Preferences/config**: `powerline` pref key, `--no-powerline` CLI flag, `ZEPTO_POWERLINE` env var
- **Code internals**: `Zepto::Chars` (`$_powerline_enabled`, `powerline_round_left/right`), `Zepto::Preferences` (`powerline`/`set_powerline`), `Zepto::CommandRegistry` (`toggle_powerline`), `Zepto::Editor::Commands` (`cmd_toggle_powerline`), `Zepto::Renderer` (many local `$powerline` variables and comments), `Zepto::Theme` (comments), `build.pl` (`$no_powerline`, `$powerline`)
- **Tests**: `tests/chars.t`, `tests/renderer.t`, `tests/syntax_rendering.t`

**Fix:** Renamed across all files: command palette label now says "Nerd Font", preference key is `nerd_font`, CLI flag is `--no-nerd-font` (with `--no-powerline` kept as backwards-compat alias), env var is `ZEPTO_NERD_FONT`, all internal variables/methods/comments updated. Also fixed a latent bug in Renderer.pm where `Zepto::Chars->get('powerline_round_left')` referenced a non-existent key (should be `round_left`). **Manual test:** Open command palette — should show "Nerd Font" not "Powerline". Run `./zepto --no-nerd-font` — should start without nerd font glyphs.
