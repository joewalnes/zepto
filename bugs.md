# Bugs

Priority scale:
- **P0**: Broken core functionality — data loss, crash, or fundamentally wrong behavior.
- **P1**: Significant usability issue — feature works but is confusing or misleading.
- **P2**: Polish issue — inconsistency, visual glitch, or minor misbehavior.
- **P3**: Cosmetic / edge case — low impact, fix when convenient.

---

## Existing bugs

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

### ~~P3: Rename "Powerline" to "Nerd Font" throughout the codebase~~ FIXED
The feature that toggles Nerd Font glyph rendering is called "Powerline" everywhere — command palette label, preference key, variable names, CLI flags, comments, docs, and tests. The correct term is "Nerd Font" (Powerline refers specifically to the status line plugin whose glyph range is a small subset of Nerd Fonts). Occurrences span:
- **UI-visible**: command palette label (`Powerline`), `README.md` references, `UI_GUIDELINES.md`, `website/src/index.html`
- **Preferences/config**: `powerline` pref key, `--no-powerline` CLI flag, `ZEPTO_POWERLINE` env var
- **Code internals**: `Zepto::Chars` (`$_powerline_enabled`, `powerline_round_left/right`), `Zepto::Preferences` (`powerline`/`set_powerline`), `Zepto::CommandRegistry` (`toggle_powerline`), `Zepto::Editor::Commands` (`cmd_toggle_powerline`), `Zepto::Renderer` (many local `$powerline` variables and comments), `Zepto::Theme` (comments), `build.pl` (`$no_powerline`, `$powerline`)
- **Tests**: `tests/chars.t`, `tests/renderer.t`, `tests/syntax_rendering.t`

**Fix:** Renamed across all files: command palette label now says "Nerd Font", preference key is `nerd_font`, CLI flag is `--no-nerd-font` (with `--no-powerline` kept as backwards-compat alias), env var is `ZEPTO_NERD_FONT`, all internal variables/methods/comments updated. Also fixed a latent bug in Renderer.pm where `Zepto::Chars->get('powerline_round_left')` referenced a non-existent key (should be `round_left`). **Manual test:** Open command palette — should show "Nerd Font" not "Powerline". Run `./zepto --no-nerd-font` — should start without nerd font glyphs.
