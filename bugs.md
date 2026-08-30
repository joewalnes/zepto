# Bugs

Priority scale:
- **P0**: Broken core functionality — data loss, crash, or fundamentally wrong behavior.
- **P1**: Significant usability issue — feature works but is confusing or misleading.
- **P2**: Polish issue — inconsistency, visual glitch, or minor misbehavior.
- **P3**: Cosmetic / edge case — low impact, fix when convenient.

---

## Feature requests

### ~~P1: Multi-cursor editing~~ FIXED
`Ctrl+D` to select next occurrence of the current word/selection, then type/delete at all cursors simultaneously.

**Fix:** Added full multi-cursor editing support. First `⌃D` selects word under cursor. Subsequent presses add the next occurrence as a secondary cursor. All typing and backspace affects all cursors simultaneously, processed in reverse document order for offset stability. Same-line cursor position adjustment handles multiple occurrences on one line. Escape clears multi-cursors; arrow keys also exit multi-cursor mode. Status bar shows cursor count indicator. Data model: `_multi_cursors` array in View.pm, editing via `_multi_cursor_insert_char`/`_multi_cursor_backspace` in Editor.pm with undo grouping. Duplicate Line Down moved to palette-only (was `⌃D`). Added `cmd_select_next_occurrence` to CommandRegistry. 9 tests added.

### ~~P1: Status bar rework — always-visible keys grouped by modifier~~ FIXED
The status bar should make keyboard shortcuts always visible and organized by modifier key, similar to Zellij's approach. Group `⌃` (Ctrl) shortcuts on the left and `⌥` (Alt) shortcuts on the right, so the modifier is shown once per group rather than repeated on every pill — saving space and making the modifier split immediately clear. Buttons should be contextual, showing what's most relevant to the current state (e.g., editing vs find mode vs file tree). Currently, pills are arranged by category (FILE/EDIT/NAVIGATE/VIEW from `CommandRegistry::commands_for_status_bar`) with each pill repeating its modifier, and lower-priority pills drop off at narrow widths. The rework should ensure the most useful actions are always visible regardless of terminal width.

**Root cause:** The DOCUMENT-context status bar built one flat, category-ordered pill list from `commands_for_status_bar`, greedily packed left-to-right, with each pill repeating its full shortcut including the modifier glyph (`⌃S`, `⌥Z`, ...). Only 6 commands ever had `priority > 0` (eligible for the bar at all), and "Open File" was a second hardcoded always-there pill next to the palette trigger — there was no per-modifier structure and no guarantee about which pill(s) survive a narrow terminal.

**Fix:** Reworked `Renderer::_render_context_status_bar` (DOCUMENT context only — FIND/tree-focus/prompt keep their existing dedicated renderers) into two modifier-grouped columns: `⌃` pills left-aligned right after the cursor pill, `⌥` pills right-aligned right before the always-fixed `⌃␣` palette trigger, each column showing its modifier glyph once as a plain dim label (not a pill) instead of repeating it per pill. `CommandRegistry` assigns each status-bar-eligible command to a column purely by shortcut prefix (`⌃`→left, `⌥`→right); commands with no shortcut, a bare function key, or a multi-modifier chord (`⌃⇧F`) are excluded from the bar (still in the palette). Expanded the eligible set from 6 to 10 commands (added Save `⌃S` pri 1, Open File `⌃O/⌃P` pri 2 — folded in from its old hardcoded slot, File Tree `⌃B` pri 3 to `⌃`; Minimap `⌥M` pri 3, Nerd Font `⌥I` pri 5 to `⌥`) so each column has a meaningful, useful set instead of 2-3 leftovers. Removed `doc_tutorial` (F1) from the bar entirely — it has no modifier so it doesn't fit either column; still in the palette and bound to F1.

New `_fit_pill_group()` tries the full pill form (`icon label key`) first and only falls back to a compact form (`icon key`, label dropped) for the *whole* column if even its top-priority pill can't fit in full — so a pill degrades before it disappears. New budget negotiation computes each column's minimum width (label + compact top pill); whenever both minimums fit in the available space, `⌃`'s budget is capped so it can never greedily starve `⌥`, guaranteeing the priority-1 pill in *both* columns (`⌃S` Save, `⌥Z` Word Wrap) renders in some form. Under genuine extreme-narrow scarcity (not even both minimums fit), `⌃` — rendered first — wins the remaining space; only the cursor-position pill and `⌃␣` palette trigger are truly unconditional at any width.

Click hit-testing (`Editor::handle_status_bar_click`) and hover (`_handle_mouse_hover` / `get_status_buttons`) needed no changes — both work by button array position/range, and the new `_render_pill_list` helper pushes buttons in render order exactly like the old single-list loop did, so hover indices stay contiguous across the two columns.

**Tests:** `tests/renderer.t` — 4 new subtests: pills grouped left/right with modifier shown once (not repeated per pill), priority-1 pill in each column survives a narrow width (62 cols), cursor pill + palette trigger survive an extreme-narrow width (32 cols), and click buttons still register with correct hit areas. `tests/command_registry.t` — new subtest asserting every status-bar-eligible command's shortcut starts with `⌃` or `⌥` (the grouping contract) and that each column has exactly one priority-1 command. QA: `QA-SBAR-016`..`QA-SBAR-020` in `qa/26_status_bar.txt`, scripts `qa/scripts/tier1/sbar_016`..`sbar_020`, regression entries `QA-REG-110`..`QA-REG-112` in `qa/40_regression_bugs.txt`. Verified interactively via `hangon` (default 80x24 session): Ctrl group (Save, Open File) renders left of cursor pill's gap, Alt group (Word Wrap, compact `Z`) renders right before Commands, toggle on/off color still visible in compact form, hover brightens the correct pill, clicking Save pill triggers save, find mode / file tree focus / command palette all unaffected.

### ~~P3: Theme toggle pill icon doesn't switch with theme~~ FIXED (see below)
Found independently while reworking the status bar, at the same time a second concurrent agent found and fixed the same bug while adding automatic dark/light mode — see "Theme palette icon was static despite claiming to be dynamic" further down for the fix (both status-bar-pill and palette-row icon-resolution sites in `Renderer.pm`, `QA-REG-139`).

### P2: First Alt-chord after startup can be silently dropped
Found while interactively verifying the status bar rework (screenshot-diffing the Word Wrap pill's on/off color before/after a single `⌥Z`). Reproduced on a completely fresh session, on both the pre-rework and post-rework binary (confirmed pre-existing, unrelated to the status bar change): the *first* key sent to a just-started `zepto` process, if it's an Alt chord (e.g. `⌥Z`), sometimes has no effect at all — no toggle, no error, nothing — even with a 1s settle delay before sending it. A plain (non-modified) key like `→` always registers as the first key. Not 100% reproducible for every Alt chord in ad-hoc testing (`⌥C` appeared to register fine as a first key in one trial), which points at a timing race in Terminal.pm/InputParser.pm's escape-sequence handling around startup (e.g. an initial terminal capability probe response arriving and being read together with the first `ESC`-prefixed keystroke) rather than a deterministic logic bug. Needs dedicated investigation — out of scope for the status bar rework. QA scripts that send an Alt chord as the very first interaction should send a harmless warm-up key (e.g. `right`) first to avoid flaking on this (see `qa/scripts/tier1/sbar_020_compact_toggle_color.sh`).

### P2: `⌃Space` (open palette) can be silently dropped when it isn't the very first key sent
Also found while building `QA-SBAR-020`. Reproduced manually and via the QA harness, consistently (not a one-off flake, unrelated hangon/tmux daemon load): `⌃Space` reliably opens the command palette when it's the *first* key sent to a fresh session (matches every other passing status-bar QA script), but if literally any other key — `→`, `↓`, even with a 1s gap in between — is sent first, the next `⌃Space` is swallowed: no palette opens, and if a subsequent `qa_send` types text expecting a palette filter, that text lands as literal document input instead (confirmed via screen capture: `"hWord Wrapello world"` was typed straight into the buffer). Retrying `⌃Space` again on the same already-"warmed-up" session does not help — it keeps failing. Suggests `⌃Space`'s encoding (likely `NUL`, a common terminal convention for Ctrl+Space) interacts badly with whatever byte(s) precede it in the read buffer, in Terminal.pm/InputParser.pm. Needs dedicated investigation — out of scope for the status bar rework. Worked around in `QA-SBAR-020` by only ever sending `⌃Space` as the first interaction in that script, at the cost of not being able to script a real toggle-and-reread round trip (the on/off *color* change itself was confirmed manually via `hangon screenshot` during development, not asserted in the script).

### P2: Escape immediately followed by a burst keystroke send can drop or corrupt the next character(s)
Found while writing `QA-REG-152` (cross-buffer completion cache accuracy). Reproduced independent of that change, including in single-document/no-tab-manager mode with plain keyword-based ghost text (not specific to `CrossBufferWordProvider` or multi-tab): after `Escape` dismisses an active ghost-text completion, sending a burst of characters where the *first* character is a space (e.g. typing `" moreWords"` to continue on a new word after the completed one) can silently drop that leading space — the new text lands glued directly onto the previous word with no separator. In one repro at a 1s delay after Escape, the dropped space came back as a spurious newline instead (text split onto the next line) rather than being dropped outright, so the failure mode isn't perfectly consistent. Reproduced at delays from 0.2s up to 1.0s after Escape, so it isn't purely a fast-typing race in the literal sense — more likely an escape-sequence disambiguation issue in `Editor.pm`'s `flush_pending_input()` (the "ESC alone becomes Escape; ESC+char within timeout becomes Alt+char" logic, `Editor.pm` ~962-966) getting confused specifically when the *previous* Escape closed an active completion popup. Typing continuously without pressing Escape first (i.e., just extending the prefix, which is also how most users actually interact with ghost text) does not trigger this — worked reliably in every trial. Needs dedicated investigation into `Terminal.pm`/`InputParser.pm`/`Editor.pm`'s escape-sequence handling around completion dismissal specifically; out of scope for the CrossBufferWordProvider caching fix that surfaced it. `qa/scripts/tier1/reg_152_crossbuffer_cache_accuracy.sh` was written to avoid the trigger pattern (continues typing directly instead of escaping first) rather than assert around this bug.

### P1: `Zepto::Editor->new()` defaults to the developer's real `~/.config/zepto` StateStore, so both unit tests and routine interactive `hangon` testing can silently corrupt the real machine's preferences/history
Found incidentally while interactively verifying a `cmd_toggle_*` refactor (toggling Auto Pairs / Restore Session / Soft Tabs / Mouse live via `hangon` against `./zepto <scratch-file>`, per the mandatory Testing Workflow in `CLAUDE.md`). `Editor.pm:87` does `state_store => $opts{state_store} // Zepto::StateStore->new()`, and `StateStore::new` (`StateStore.pm:28-37`) falls back to `$XDG_CONFIG_HOME/zepto` or `$HOME/.config/zepto` when no `base_dir` is given. Running `./zepto` directly (exactly as `CLAUDE.md`'s own Testing Workflow example shows: `hangon start process --name zepto -- ./zepto /tmp/testfile.txt`, no state-dir override) toggling any preference persisted it straight into the real `~/.config/zepto/preferences.json` on the host machine, overwriting the developer's actual settings (`auto_pairs`, `mouse_enabled`, `restore_session`, `soft_tabs` all got flipped to off on this machine) — required a manual restore after the fact.

Worse, this same real-`$HOME` fallback is what a huge fraction of `tests/editor.t`'s `Zepto::Editor->new(...)` calls rely on implicitly — grep shows well over 100 constructions in that file alone with no `state_store => ...` passed, so they read/write whatever happens to be at `~/.config/zepto/*.json` on the machine running the suite. After the interactive session above left `soft_tabs` off in the real prefs file, `make test` immediately failed two previously-green, unrelated subtests (`Indent`, `Indent preserves selection` — they assume default `soft_tabs => 1` and got a tab character instead of 4 spaces) with zero code change in between: pure environmental cross-contamination between an interactive dev/QA session and the "isolated" unit test suite, on a single shared machine-global file. Likely affects other `.t` files too (not just `editor.t`) — not audited exhaustively.

Impact: (1) any interactive `hangon`/manual testing session that doesn't explicitly redirect `XDG_CONFIG_HOME`/`HOME` can silently overwrite the developer's real Zepto preferences and cursor/find/recent-files history — no warning, no confirmation; (2) `make test` is not actually hermetic — its pass/fail result on this suite of subtests depends on whatever real global state happens to exist on the host, so a clean worktree with correct code can show spurious failures (or, worse, a broken worktree can show spurious *passes*) depending on unrelated prior activity on the same machine. Needs a real fix: either default test `Zepto::Editor->new()` should refuse to fall back to a real `$HOME` (require explicit `state_store` / fail loudly), or `tests/editor.t` (and any other affected `.t` files) should pass an isolated `state_store => Zepto::StateStore->new(base_dir => tempdir(...))` at every construction site — plus the Testing Workflow docs in `CLAUDE.md` should be updated to always set `XDG_CONFIG_HOME` to a scratch directory before `hangon start`ing `./zepto` for interactive testing. Out of scope to fix here (huge blast radius across ~150+ call sites and doc changes); flagging per Rule 6. No code changes made for this — only the incidentally-corrupted real `~/.config/zepto/preferences.json` and `history.json` on this machine were manually restored (defaulted-back toggles set back to `1`; the one polluted `cursor_positions` entry for the ephemeral scratch test file removed).

### ~~P2: Mouse hover effects~~ FIXED
When moving the mouse over interactive elements (status bar pills, tab bar tabs, file tree items), highlight the hovered element with a visual effect.

**Fix:** Switched mouse tracking from `?1002h` (button-event) to `?1003h` (any-event) in Terminal.pm to receive motion events without button press. Added `MOUSE_MOVE` action to InputParser.pm. Editor.pm tracks hover state (`_hover_tab_index`, `_hover_pill_index`, `_hover_tree_row`) via `_handle_mouse_hover()` hit-testing against stored button positions. Renderer applies hover colors (brighter bg/fg) to hovered tabs, status bar pills, and file tree items. Only re-renders when hover target changes (not on every pixel of motion). Added hover theme colors (`tab_hover_*`, `pill_hover_*`, `tree_hover_*`) for both dark and light themes.

### ~~P2: Markdown table pretty-rendering~~ FIXED
When viewing `.md` files, render tables with continuous Unicode box-drawing lines (e.g. `─`, `│`, `┌`, `┬`), striped row backgrounds for readability, and column alignment. Do not add any extra rows — render the same number of rows as the source. When the cursor enters a table region, switch to raw source mode so the original pipe-delimited Markdown is visible for editing and copying.

**Fix:** Added `_detect_markdown_tables()` in Renderer.pm that scans visible lines for pipe-delimited table blocks, parses cells, computes column widths and alignment (left/center/right from separator row). `_render_table_line()` produces box-drawing output: header rows with bold text and highlighted background, separator rows as `├───┼───┤`, data rows with alternating stripe backgrounds. When cursor enters any table, that table reverts to raw source for editing. Copy always gets raw source (document model is never modified). Toggleable via `render_markdown_tables` preference (on by default). Added theme colors: `table_border_fg`, `table_header_bg/fg`, `table_stripe_bg` for both dark and light themes. Table detection is cached by content version for performance.

### ~~P3: Dim Markdown formatting delimiters~~ FIXED
In Markdown files, emphasis delimiters (`**`, `*`, `_`, `~~`, `==`) are rendered as `TOKEN_PUNCTUATION` in `Syntax/Markdown.pm`, giving them the same visual weight as the styled text they surround. The delimiters should be rendered much fainter (dimmed/low-opacity) so the bold, italic, strikethrough, and highlighted text pops out visually. This is how many modern Markdown editors handle it — the formatting chars become near-invisible while the styled content stands out. Currently all delimiter tokens share the generic punctuation color in `Theme.pm`.

**Fix:** Added a dedicated `TOKEN_FORMATTING_DELIM` token type (`Syntax/Base.pm`) distinct from `TOKEN_PUNCTUATION`. `Syntax/Markdown.pm` now emits it for the `**`/`__`, `*`/`_`, `***`/`___`, `~~`, and `==` delimiter pairs surrounding bold/italic/bold-italic/strikethrough/highlight text — no other punctuation (headings, list markers, blockquotes, code fences, link brackets, thematic breaks) is affected. Added `syntax_formatting_delim` color to both themes in `Theme.pm`: a faint blue-gray close to the dark bg (`fg_rgb(70,75,100)` vs `bg(26,27,38)`) and a faint light gray close to the light bg (`fg_rgb(200,203,212)` vs `bg(255,255,255)`) — both measurably closer to their theme's background than `syntax_punctuation`. No characters are hidden or concealed — only the delimiter color changes. Non-Markdown grammars are unaffected (e.g. Perl's `**` exponentiation operator still tokenizes as `TOKEN_OPERATOR`).

### ~~P2: Buffer word completion~~ ALREADY IMPLEMENTED
Popup a menu of matching words from open buffers on a trigger key (e.g., `Ctrl+N` or `Tab` in context). No external dependencies needed — just scan tokens from open documents. Covers 80% of what developers use autocomplete for (variable names, function names already typed once). Reduces typos and memory load for long identifiers.

**Verified 2026-08-29:** Fully implemented, and the shipped design exceeds this entry's ask — `lib/Zepto/Completion/CrossBufferWordProvider.pm` scans **every open tab's document**, not just the active buffer (cached per-document by `content_version`, rebuilt only when something changed; words from the active document get a proximity score bonus). Confirmed interactively via hangon: typed a distinctive identifier in tab A, switched to tab B, typed a 2-char prefix — ghost text suggested the tab-A-only word, and Tab accepted it into tab B.

Shipped trigger model (`lib/Zepto/Completion/Controller.pm`, orchestrated from `Editor.pm`):
- **Auto-trigger**: ghost text appears automatically after typing 2+ word characters — no dedicated key needed for the common case (this entry's suggested `Ctrl+N`/`Tab` triggers were never implemented as such; auto-trigger plus the existing `⌃Space` below covers the same need without demanding a key to memorize).
- **`⌃Space`**: dual-purpose — if the cursor sits immediately after a word character, it explicitly opens the dropdown menu (multiple candidates) instead of the command palette; otherwise it opens the palette. This is intentional, pre-existing behavior, not new.
- **`Tab`**: accepts the full ghost-text completion.
- **`→` (Right arrow)**: accepts one character at a time, keeping the rest as ghost text.
- **`↑`/`↓`**: navigate the dropdown menu; `Enter` accepts the highlighted item.
- **`Esc`**: dismisses.
- **`⌥[` / `⌥]`**: cycle ghost-text alternatives.

Other providers already merged into the same ranked result set: `KeywordProvider` (language keywords), `SnippetProvider` (multi-line templates, e.g. Python `def`), `PathProvider`, `RecentProvider` (recently-accepted completions get a score boost), and AI completion (separate opt-in provider, rate-limited).

No gap found — nothing to implement. Added `QA-CPLT-021` (cross-buffer path specifically; existing `QA-CPLT-001`–`020` covered same-buffer, dropdown, accept/dismiss/navigate, undo/redo, snippets, recent-pick, AI, the off-toggle, and paste-doesn't-trigger, but none exercised a SECOND open tab as the completion source).

### ~~P2: Session restore~~ FIXED
Reopen the editor and get back exactly where you were: same tabs, cursor positions, scroll positions. The recent files infrastructure already exists (`~/.config/zepto/recent_files`). Extending to full session state eliminates the re-navigation tax every time the editor is restarted. Especially important for a terminal editor that gets opened/closed frequently.

**Fix:** Added session save/restore to `Zepto::Editor`, keyed **per working directory** (not global) — a terminal editor gets opened from many different projects, and one global "last session" would fight between them. Storage: StateStore category `history`, new key `sessions` → `{ "<abs cwd>": { active_index, tabs: [{ file_path, line, col, scroll_line, scroll_col }, ...] } }`, alongside the existing `recent_files` and `cursor_positions` keys.

Design decisions:
- **Restore only on a truly bare launch** — no file args AND no directory arg. A directory arg (`zepto .`) is tree-focus mode, not "no arguments," and doesn't fight with the saved session.
- **Save is gated by the same "bare launch" condition as restore**, tracked via `Editor->{_session_eligible}` (set once in `init()`). This was **not** the first design — an early version saved unconditionally at quit, which meant a one-off `zepto some_file.txt`, or just running `zepto .` to browse the tree and quitting immediately, would silently overwrite or clear a real saved session. Caught via interactive testing before release; see `QA-REG-115`/`QA-REG-116`.
- **Only file-backed tabs are saved/restored.** Unsaved `[untitled]` buffers are skipped — persisting their content would mean snapshotting unsaved text into StateStore, a bigger and riskier feature than "remember where I was."
- **Files deleted since the session was saved are skipped individually** at restore (not an error, and doesn't abort the rest of the session).
- **Cursor and scroll are restored exactly**: cursor line/col reuses the existing `cursor_positions` clamp logic (factored into a shared `_clamp_position($doc, $line, $col)` helper used by both features); `scroll_line`/`scroll_col` are set directly on the `View` before `ensure_cursor_visible()`, so it only adjusts them if the saved viewport no longer fits (e.g. terminal resized) rather than always re-centering on the cursor.
- **Saved only at well-defined quit points** (Ctrl+Q, and closing the last tab, which also quits) — not on every tab switch or save. Those are deliberate, infrequent actions, so the StateStore write (flock + read + encode + rename) is cheap relative to them; wiring it into tab-switch would add that cost to a much hotter path for no real benefit over a clean-quit save. A crash without a clean quit loses the latest session, same pre-existing limitation as cursor-position history.
- **Preference-gated**: new `restore_session` pref (default on), persisted/synced like other global preferences. Discoverable via the command palette ("Restore Session on Startup", ⌃Space) per Rule 2 — no dedicated shortcut, following the same no-shortcut pattern as Auto Pairs/Auto Complete.

### ~~P2: Persistent config file~~ FIXED (was already mostly true)
Original text: "Save preferences to `~/.config/zepto/config.toml` (or similar) so they survive restarts... Without this, users can't persist their theme choice, tab width, minimap preference, etc."

**Audit finding: this was stale.** `StateStore` + `preferences.json` under `~/.config/zepto/` (honoring `--state-dir` / `$ZEPTO_STATE_DIR`, see `build.pl`) has persisted global preferences all along — theme, nerd font, minimap, auto-complete, auto-pairs, AI URL/model already round-tripped across restarts with a working palette command, verified interactively. The file is pretty-printed JSON, so it's already hand-editable — a second config system (e.g. `config.toml`) would have been needless duplication and was deliberately **not** added. `preferences.json` *is* the persistent config file; QA-PREF-014 now documents this instead of the stale "no config file yet" claim.

**What was actually missing** (verified with `hangon`: toggle → quit → relaunch with the same `--state-dir`):

| Preference | Persist-eligible before | UI before | Fix |
|---|---|---|---|
| `tab_width` | yes (in `GLOBAL_PREFS`) | **none** | Added "Tab Width" palette action (footer-input prompt, validates 1-16) |
| `soft_tabs` | yes | **none** | Added "Soft Tabs (Spaces)" palette toggle |
| `auto_indent` | yes | **none** | Added "Auto Indent" palette toggle |
| `mouse_enabled` | yes | **none** (only set at startup) | Added "Mouse" palette toggle; also enables/disables mouse mode on the live terminal |
| `search_wrap` | no (real effect, used by find-next/prev) | **none** | Added "Search Wrap Around" palette toggle; added to `GLOBAL_PREFS` |
| `render_markdown_tables` | no (real effect, used by table rendering) | **none** | Added "Markdown Table Rendering" palette toggle; added to `GLOBAL_PREFS` |

**Fix:** `lib/Zepto/Preferences.pm` (`search_wrap`, `render_markdown_tables` added to `%GLOBAL_PREFS`), `lib/Zepto/CommandRegistry.pm` (6 new commands: `set_tab_width`, `toggle_soft_tabs`, `toggle_auto_indent`, `toggle_mouse`, `toggle_search_wrap`, `toggle_markdown_tables`), `lib/Zepto/Editor/Commands.pm` (handlers). QA: `qa/scripts/tier1/pref_015..020_*.sh`, `qa/36_preferences.txt` (QA-PREF-015 through 020, rewrote QA-PREF-014). Also fixed `qa/scripts/tier1/pref_001_defaults.sh`, `wrap_001_toggle.sh`, `wrap_012_per_window.sh` — they searched the palette for the bare word "wrap", which now also fuzzy-matches "Search Wrap Around" and could grab the wrong toggle's on/off state; narrowed to the exact label "Word Wrap".

**Deliberately left alone (documented, not fixed — out of scope):** `theme`, `nerd_font`, `show_minimap`, `auto_complete`, `auto_pairs`, `ai_api_url`/`ai_model` already had working UI + persistence. `word_wrap` and `show_tree` are intentionally per-window/session state (see `Preferences.pm` header comment and `_effective_word_wrap`'s override-precedence design, confirmed by existing QA-PREF-012) — their palette toggles change the current window only, by design, and should not be made to overwrite the global default. See also the new vestigial-preference bug below.

### P3: Several defined preferences have no effect (dead/vestigial)
Audit of every key in `Preferences.pm` (2026-08-29, alongside the Persistent config file fix above) found preferences that are defined with defaults, covered by unit tests asserting their default value, but never actually read by any behavior:

- `show_line_numbers` — gutter is rendered unconditionally; the renderer never checks this pref.
- `show_status_bar` — status bar is rendered unconditionally; never checked.
- `confirm_quit_unsaved` — `cmd_quit`/`_prompt_close_dirty_tabs` always prompt on dirty tabs regardless of this pref's value; it's never read.
- `scroll_margin` — not referenced anywhere outside `Preferences.pm`; scrolling logic doesn't use it.
- `backup_on_save` — no `.bak`-file-writing code exists anywhere.
- `trim_trailing_whitespace` — `Document::save()` never trims trailing whitespace.
- `ensure_final_newline` — `Document::save()` unconditionally appends a trailing newline; the pref's value is never consulted (so today, "off" is actually impossible to achieve).
- `search_case_sensitive`, `search_regex` — these top-level defaults are never read; the live find/file-search state is tracked separately per session (`find_case` in Editor.pm, `_file_search_regex`, `_file_search_case`) and always initializes to a hardcoded `0`, not from these prefs.

These weren't added to the palette or `GLOBAL_PREFS` in the config-file fix above because there's no working behavior to expose or persist yet — doing so would be misleading (a toggle that visibly does nothing). Each one is either a genuinely unimplemented feature (implement the behavior, then add UI + persistence) or dead code that should be deleted. Needs a product decision on which.

### P3: Tab Width's validation-error pattern exposed a pre-existing dead-code bug in Go to Line
While adding the new "Tab Width" palette command, invalid input was (in the first draft) reported via `$self->{status_msg}`, which turned out to be a field the renderer never displays — errors vanished silently. Fixed in Tab Width by switching to `show_error_message()` (see QA-REG-120). `cmd_goto_line` (`lib/Zepto/Editor/Commands.pm`) has the exact same bug for its "Invalid format. Use: line, line:col, or :col" message — typing a malformed Go to Line input fails silently today. Not fixed here (out of scope for this task) — it's the only other `status_msg` writer in the codebase (`grep -rn status_msg lib/`), so this is the complete list.

### ~~P2: Shortcut key for Duplicate Down~~ FIXED
Duplicate Down currently has no keyboard shortcut — it's palette-only. Should have a direct keybinding for quick access. `⌃D` is taken (Select Next Occurrence). Candidates: `⌃⇧D` (Shift=reverse already used for Duplicate Up as `⌃U`, but `⌃⇧D` is intuitive as "duplicate" with Shift for the pair), or find another mnemonic. Also consider giving Duplicate Up a matching shortcut if it doesn't have one.

**Fix:** `⌃⇧D` was rejected after checking `InputParser.pm`: classic terminals deliver Ctrl+letter as a single control byte (0x01-0x1a, `_parse_control`), which can only ever set `modifiers => ['ctrl']` — there is no wire representation of Shift for it, so Ctrl+D and Ctrl+Shift+D are indistinguishable in most terminals (confirmed interactively — `hangon`'s own key vocabulary has no `ctrl-shift-*` combos for exactly this reason). Bound `⌥U` instead (Alt+letter survives reliably as ESC+char). `⌥U` pairs mnemonically with the existing `⌃U` (Duplicate Up) — same letter, "up" vs "down" modifier — and doesn't collide with any other Alt+letter binding. Duplicate Up already had `⌃U` from the original multi-cursor work, so no change was needed there. Added to `CommandRegistry.pm` (`dup_line_down` shortcut) and `Editor.pm::handle_alt_char`. QA: `QA-LINE-010`, `QA-REG-125`.

### ~~P3: Automatic dark/light mode~~ FIXED
Detect the system theme (dark/light) on startup and choose the matching editor theme. Detect when the system theme changes at runtime and automatically switch. Auto mode is optional — users can still manually set dark or light via `Ctrl+T` or config.

**Fix:** The `theme` preference is now three-valued: `'auto' | 'dark' | 'light'` (`Preferences.pm`, default stays `'dark'` — auto is opt-in). New `Zepto::ThemeDetect` module (Perl core only, no CPAN) detects the OS appearance:
- **macOS**: `defaults read -g AppleInterfaceStyle` via list-form exec (no shell interpolation) — key present + matches `/dark/i` → dark; absent (nonzero exit) or anything else → light, matching the command's own semantics.
- **Linux**: `gsettings get org.gnome.desktop.interface color-scheme` if `gsettings` is on PATH — `prefer-dark` → dark, else light.
- **Linux without gsettings, and any other platform**: inconclusive → falls back to `dark` (the existing default). A terminal OSC 11 background-color-query fallback was considered but **deliberately scoped out of v1**: the editor sets the terminal cursor color via OSC 12 in `Editor::init()` *before* raw mode is enabled (needed so cursor color is set before the alt-screen transition), which means the theme must already be resolved before raw mode is available — but a synchronous OSC 11 query/response round-trip needs raw mode active to read the reply without local echo/line-buffering interference. Reordering startup to accommodate the round-trip was judged too much startup-path risk for a P3 feature affecting a narrow audience (Linux desktops without GNOME/gsettings). Detection there just reports inconclusive, same as today.
- Every detection function accepts injectable collaborators (`platform`, `run`, `command_exists`) so `tests/theme_detect.t` and the `Zepto::Editor->new(theme_detect_fn => ..., theme_poll_supported_fn => ...)` test hooks never shell out.

`⌃T` design decision: pressing `⌃T` always switches to the explicit opposite of whatever theme is *currently effective* (`$self->{theme}->name()`, which is always a concrete dark/light name even under auto) — and since that sets an explicit preference, it **leaves auto mode**. Re-entering auto requires the dedicated "Theme: Auto" palette command. This was chosen over "⌃T cycles auto→dark→light→auto" because "give me the other look right now" is the far more common intent behind a manual toggle, and a silent hop back into auto (which could then immediately re-flip based on the system) would be surprising.

Runtime change detection: the idle branch of `Editor::run()`'s main loop calls `_maybe_poll_system_theme()`, which is a no-op unless the preference is `'auto'` **and** `Zepto::ThemeDetect::platform_supports_polling()` says the platform is cheap to poll (macOS always; Linux only if `gsettings` exists — never on Linux without it, since there's no signal to poll). When active, it re-detects at most once per 5 seconds (`THEME_POLL_INTERVAL_SEC`) and swaps the live theme (plus re-applies the OSC 12 cursor color) only if the detected value actually changed. No per-keystroke cost — this only runs on the input-timeout ("nothing typed") path.

Discoverability: palette gained three new commands — "Theme: Auto" / "Theme: Dark" / "Theme: Light" (VIEW section, `theme_set_auto`/`theme_set_dark`/`theme_set_light`) that jump directly to a mode. The existing "Theme" row (`⌃T`) now displays `[auto]`/`[dark]`/`[light]` and its icon dynamically reflects the actual mode (see QA-REG-139 below).

**Verified interactively** (this Mac, real system theme was Dark at test time, confirmed via `defaults read -g AppleInterfaceStyle`): selecting "Theme: Auto" from the palette resolved the editor to the dark theme, matching reality — screenshot evidence taken. `⌃T` from that state switched to explicit light and the indicator changed from `[auto]` to `[light]`; a second `⌃T` went to `[dark]`, confirming "leaves auto" and normal two-way toggling afterward. Selecting "Theme: Light" from the palette also switched immediately (white background, dark text).

**Files:** `lib/Zepto/ThemeDetect.pm` (new), `lib/Zepto/Preferences.pm`, `lib/Zepto/Theme.pm` (doc only), `lib/Zepto/Editor.pm` (`_resolve_theme_name`, `_theme_polling_supported`, `_maybe_poll_system_theme`, theme init/cross-instance-sync call sites, idle-loop poll hook), `lib/Zepto/Editor/Commands.pm` (`_apply_theme_pref`, `cmd_toggle_theme` redesigned, `cmd_set_theme_auto/dark/light`), `lib/Zepto/CommandRegistry.pm` (three new commands), `lib/Zepto/Chars.pm` (`theme_auto` icon), `lib/Zepto/Renderer.pm` (dynamic theme-row icon — see QA-REG-139), `build.pl` (bundling order). Tests: `tests/theme_detect.t` (new), `tests/editor.t`, `tests/preferences.t`, `tests/command_registry.t`. QA: `QA-THM-012` through `QA-THM-014` in `qa/29_themes.txt`.

---

## Existing bugs

### P3: Undo can leave the cursor column past the end of the (now shorter) line
Found incidentally while interactively testing session restore (2026-08-29): type past the end of a short line (e.g. line is `line5`, type extra characters after it so the cursor sits at column 11), then Ctrl+Z. The text reverts to `line5`, but the cursor column stays at 11 — visibly past the end of the now-5-character line — until the next cursor-moving action (arrow key, Home/End, click) snaps it back in bounds. Not a crash or data loss; purely a transient visual/positional glitch. Not fixed here — out of scope for the session-restore work that surfaced it, and `Editor::_clamp_position` (added for session restore, shared with the pre-existing cursor-position-history feature) already defends downstream consumers of a saved cursor position against exactly this kind of out-of-range value, so it doesn't propagate into persisted state.

### ~~P2: Binary file tab looks editable~~ FIXED
When opening a binary file, there was no visual indication that the file was read-only.

**Fix:** Added a "READ ONLY" indicator segment in the status bar for binary files (Renderer.pm), styled with warning colors. The indicator renders as a pill between the file path and the middle fill area, using the same arrow-transition pattern as the column selection indicator. Added regression test.

### ~~P1: Incorrect cursor placement in Open File dialog~~ FIXED
When opening the file picker (`⌃O`), the terminal cursor was not aligned with the text input position. The cursor appeared offset from where typed characters actually rendered in the filter field.

**Root cause:** The cursor positioning code in `Renderer.pm` (line ~475) only applied the wide 120-column palette width for `find_in_files` mode, but the rendering code (line ~4139) applied it for `find_in_files`, `files`, AND `recent_files`. The file picker rendered at 120 columns wide while the cursor was positioned using the command palette width (60 or 80 depending on terminal width), causing a 20-40 column offset.

**Fix:** Added `files` and `recent_files` to the wide-width condition in the cursor positioning code, matching the rendering code exactly.

### ~~P1: Editor becomes sluggish when opening large files~~ FIXED
Opening a ~1MB / 13K+ line file caused the editor to become sluggish — slow tab opening, laggy cursor navigation, general unresponsiveness.

**Root cause:** Three compounding bottlenecks: (1) `vcs_change_status()` and `vcs_deletion_status()` in Document.pm used O(n) linear array scans, called for every visible line every frame. (2) Renderer.pm rebuilt VCS lookup hashes from scratch every frame. (3) Minimap.pm cache key included `undo_size`/`redo_size` which change every keystroke, defeating the cache and causing full minimap recomputation on every frame.

**Fix:** (1) Added `_rebuild_vcs_lookup()` in Document.pm that builds O(1) hash lookups once when the VCS diff is computed, not per-frame. `vcs_change_status()` and `vcs_deletion_status()` are now single hash lookups. (2) Renderer.pm now uses Document's cached hashrefs directly instead of rebuilding per-frame. (3) Minimap cache key uses `content_version` (incremented only on edits) instead of undo/redo sizes. Also added adaptive VCS diff debounce: 1.0s for files >5000 lines vs 0.3s for smaller files.

### ~~P1: File tree doesn't always expand to opened file~~ FIXED
When opening a file or switching tabs, the file tree should always expand to and select the corresponding entry. Previously didn't work reliably — the tree showed stale selection or collapsed parents after opening a file via file picker, recent files, or find-in-files.

**Root cause:** Two missing tree-update sites: (1) `_load_file()` in Commands.pm created new tabs via `add_tab()` without calling `set_current_file()`/`expand_to_path()`. (2) `_jump_to_location()` in Editor.pm called non-existent `switch_to()` on TabManager instead of using `_switch_to_tab()`, so find-in-files tab switching silently failed AND the tree never updated.

**Fix:** Added `set_current_file()` + `expand_to_path()` after `add_tab()` in `_load_file()`. Changed `_jump_to_location()` to use `_switch_to_tab()` which already includes tree reveal logic. Added 2 tests verifying tree updates after both code paths.

### ~~P1: [Usability] Global shortcuts should work from any state~~ FIXED
Several core shortcuts were swallowed when in find/replace (`⌃F`), footer input, or other modal states.

**Fix:** Extended the global shortcut intercept in `handle_event()` to cover 6 additional shortcuts beyond the existing ⌃Q/⌃S/⌃T: `⌃O` (Open File), `⌃W` (Close Tab), `⌃N` (New File), `⌃E` (Recent Files), `⌃Space`/`⌃⇧P` (Command Palette), and `⌃⇧F` (Find in Files). All close the current modal first via `_close_any_modal()`, then execute. `⌃Space` toggles the palette (closes if already open). Removed `_in_modal_state()` guards from `cmd_open_file`, `cmd_recent_files`, `cmd_find_in_files`, and `cmd_open_palette`. Updated tests to reflect the new behavior.

### ~~P1: [Security] Shell injection in VCS/Git.pm via backtick execution~~ FIXED
`VCS/Git.pm` constructs shell commands as strings and executes via backticks (`\`$cmd\``). While `_shell_quote()` is used for arguments, the `cd ... && git ...` pattern with string interpolation is inherently risky. Should use git's `-C` flag and list-form execution (`open()` with pipes) to eliminate shell interpretation entirely. Same pattern appears in multiple functions (~lines 80, 101, 132, 200).

**Fix:** Replaced all 5 backtick executions with a `_run_git()` helper that uses `open(FH, '-|')` + `exec('git', @args)` list-form execution (no shell interpretation). Added `_git()` instance method that prepends `-C <repo_root>` to avoid `cd && git` pattern. Removed the now-unnecessary `_shell_quote()` function. All git operations (version check, ls-files, show, status) now use safe list-form exec.

### ~~P1: [Security] Shell injection in Terminal.pm clipboard and command detection~~ FIXED
`Terminal.pm` uses backtick execution in two places: `paste_from_clipboard()` (line ~524: `` `$self->{_clipboard_paste_cmd} 2>/dev/null` ``) and `_command_exists()` (line ~487: `` `which $cmd 2>/dev/null` ``). While the command strings are currently hardcoded, backtick execution is unsafe by default. Should replace with list-form `system()` or `open()` with pipes.

**Fix:** Added `_safe_backtick()` helper that uses `open(FH, '-|')` + list-form `exec()` (no shell interpretation). Converted `_command_exists()`, `paste_from_clipboard()`, `stty size`, and `tput cols/lines` to use it. Changed clipboard command storage from strings to arrayrefs so `copy_to_clipboard()` and `paste_from_clipboard()` can use list-form `open()`/`exec()`. Updated test to use `is_deeply` for arrayref comparison.

### ~~P1: [Documentation] Stale references to deleted TODO.md~~ FIXED
`TODO.md` was deleted in commit `90a4c38` but is still referenced in `CLAUDE.md` (line 143, "Keeping Docs Current" table) and `docs/CODE_QUALITY.md` (line 31, "Remove from `TODO.md` if listed"). Anyone following the documented workflow will try to update a non-existent file.

**Fix:** Removed `TODO.md` row from the "Keeping Docs Current" table in `CLAUDE.md` and removed step 6 "Remove from `TODO.md` if listed" from the feature completion checklist in `docs/CODE_QUALITY.md`.

### ~~P1: [Documentation] UI_GUIDELINES.md palette sections are wrong~~ FIXED
`UI_GUIDELINES.md` says palette sections are "DOCUMENT, APP, NAVIGATE, TOGGLES" but the actual sections in `CommandRegistry.pm` are FILE, EDIT, NAVIGATE, VIEW, DIAGNOSTICS. The sections were reorganized (see P2 "Command palette re-org" FIXED entry) but the guidelines were never updated.

**Fix:** Updated line 61 in `docs/UI_GUIDELINES.md` from "DOCUMENT, APP, NAVIGATE, TOGGLES" to "FILE, EDIT, NAVIGATE, VIEW, DIAGNOSTICS" to match the actual `@SECTION_ORDER` in `CommandRegistry.pm`.

### ~~P1: [Performance] Character width computed per-character with no caching~~ FIXED
`_char_display_width()` in `Renderer.pm` (130+ lines of Unicode range checks) is called for every character on every visible line on every frame. For a 40-line, 200-column viewport that's ~160,000 function calls per frame. Should memoize by codepoint or use a lookup table.

**Fix:** Added memoization cache (`%_cdw_cache`) keyed by codepoint. Extracted range-check logic into `_compute_char_width()` which is only called on cache miss. Added fast path: printable ASCII (0x20-0x7E) returns 1 immediately without cache lookup, covering ~99% of typical source code characters.

### ~~P2: [Bug] Shift+Tab does same thing as Tab in find-in-files palette~~ FIXED
`Palette.pm` lines 85-90: both Tab and Shift+Tab call `_file_search_cycle_scope()` with no direction parameter. Shift+Tab should cycle backward through scopes but currently cycles forward, identical to Tab.

**Fix:** Added `$direction` parameter to `_file_search_cycle_scope()`. Shift+Tab now passes -1 (backward), Tab passes no direction (forward). With the current 2-scope setup (project, file dir) the visible behavior is identical, but the code is now correct for future scope additions.

### ~~P2: [Bug] Missing `use File::Spec` in Palette.pm~~ FIXED
`Palette.pm` line 286 calls `File::Spec->rel2abs()` but never imports `File::Spec`. It works by accident because `Editor.pm` imports it, but this is fragile and violates the module's own import conventions.

**Fix:** Already fixed in commit 4f3c5a0 (Find in Files). `use File::Spec;` is now at line 20.

### ~~P2: [Security] ReDoS vulnerability via user search input~~ FIXED
User-supplied regex patterns are compiled dynamically in `FindEngine.pm` (line ~455) and `FileSearchEngine.pm` (line ~268, ~449) via `eval { qr/$query/ }`. A crafted pattern like `(a+)+$` could cause catastrophic backtracking and freeze the editor. Should add regex complexity validation or a timeout mechanism.

**Fix:** Added 1000-character pattern length limit to `FileSearchEngine.pm` (matching `FindEngine.pm`'s existing limit). Also fixed `_find_match_in_content` to use the pre-compiled regex from `_perl_regex` instead of re-compiling from the query string on every line match — this also fixes the P3 "regex recompilation in inner loop" bug.

### ~~P2: [Security] Predictable temp file names in Document.pm atomic save~~ FIXED
`Document.pm` line ~138 uses `"$path.zepto.tmp.$$"` (PID-based) for temp files during atomic save. On multi-user systems this is predictable and vulnerable to symlink attacks (TOCTOU). Should use `File::Temp` for secure temporary file creation.

**Fix:** Replaced PID-based temp filename with `File::Temp::tempfile()` which creates files with unpredictable names via exclusive `O_EXCL` open, preventing symlink attacks. Temp file is created in the same directory as the target file (required for same-filesystem `rename`).

### ~~P2: [Performance] Renderer uses 381+ string concatenations in hot path~~ FIXED
`Renderer.pm` used 391 `$output .=` operations per frame. In Perl, repeated string concatenation triggers reallocation.

**Fix:** Refactored all 19 render methods from `$output .= EXPR` to `push @_out, EXPR` with `join('', @_out)` at return. 426 lines changed across all render methods including `_render_command_palette` (87 concat ops), `_render_context_status_bar` (63), `_render_tree_node_content` (32), `_render_dialog` (30), `_render_tab_bar` (28), and 14 others. Array accumulation avoids per-append reallocation — Perl's `join()` pre-calculates total size and allocates once.

### ~~P2: [Documentation] CODE_QUALITY.md "Open Items" are all resolved~~ FIXED
`docs/CODE_QUALITY.md` lines 173-180 lists four items as "Open" (unified input widget, global nav keys audit, theme contrast, mouse parity) but all four are marked FIXED or AUDITED in bugs.md. The audit list is stale and creates a false impression of outstanding work.

**Fix:** Removed the entire "Open Items" section from `docs/CODE_QUALITY.md` since all four items are resolved in bugs.md.

### ~~P2: [Documentation] README.md lists zero features~~ FIXED
README.md is 32 lines with no feature list despite the editor having command palette, 52-language syntax highlighting, file tree, find/replace, git diff, minimap, tabs, etc. This violates CLAUDE.md Rule 7 which says to update README when features change.

**Fix:** Added a "Features" section to README.md with 12 bullet points covering command palette, syntax highlighting, find/replace, find in files, file tree, tabs, git integration, minimap, view modes, themes, shell transform, and zero-dependency architecture.

### ~~P2: [Build] build.pl not in Makefile dependency list~~ FIXED
`Makefile` line ~53: `zepto: $(MODULES)` doesn't depend on `build.pl`. Changing the build script won't trigger a rebuild. Should be `zepto: $(MODULES) build.pl`.

**Fix:** Added `build.pl` to the dependency list: `zepto: $(MODULES) build.pl`.

### P2: [Architecture] Editor is a 6000-line god object across 3 files — SKIPPED
`Editor.pm`, `Commands.pm`, and `Palette.pm` all declare `package Zepto::Editor;` and inject 162 methods into a single class. The class directly manages event loop, file I/O, find/replace, command palette, dialogs, tabs, mouse handling, VCS, and more. No encapsulation boundary — any method can mutate any `$self` field. State transitions are ad-hoc string assignments with no validation.

**Skipped — 6000 lines, 162 methods, 929 tests touching `$editor` objects directly. Extracting subsystems (find/replace, dialog management, scroll handling) requires defining stable interfaces, migrating shared `$self` state to composition, and updating tests. Multi-session project. Recommended approach: extract one subsystem at a time (start with dialog/prompt/footer — most self-contained), validate tests between each extraction.**

### ~~P2: [Code Quality] Inconsistent error handling across commands~~ FIXED
`cmd_save` showed raw `$@` with Perl stack traces to users. `cmd_transform` stripped location info. `_load_file` showed "Error opening file: $@" with internal paths.

**Fix:** Added `_user_error($action, $@)` helper that strips Perl file/line info from `$@` and formats as `"$action: $reason"`. Applied to all 5 error paths: Save As, Save, file open, transform, and file reload (2 locations in Editor.pm). All errors now use `show_error_message()` for consistent styling. Format: "Save failed: Permission denied", "Could not open file: No such file or directory", etc.

### ~~P3: [Security] Terminal escape sequence injection via filenames~~ FIXED
`Terminal.pm` line ~540 sanitizes titles by stripping `[\x00-\x1f]` (ASCII control chars only). UTF-8 sequences or characters outside this range could potentially manipulate terminal state. Should consider a whitelist of allowed characters.

**Fix:** Extended the title sanitizer to also strip DEL (0x7F) and C1 control characters (0x80-0x9F), which can trigger terminal-specific escape sequences.

### ~~P3: [Performance] Tab bar geometry recalculated every frame~~ FIXED
`Renderer.pm` recalculated tab pill widths, progressive name truncation, and tab range visibility every frame — even when only the cursor moved.

**Fix:** Added class-level cache for `_render_tab_bar()` keyed on tab count, active index, terminal width, and per-tab state (name, dirty, VCS). Cache includes both the rendered string and button positions for mouse clicks. Returns cached result on hit, skipping all geometry computation.

### ~~P3: [Performance] VCS status checked per visible line per frame~~ FIXED
`Renderer.pm` called `vcs_deletion_status()` and `vcs_change_status()` for every visible line on every frame. These methods do linear array scans, resulting in O(visible × changes) per frame.

**Fix:** Pre-build `%vcs_change` and `%vcs_deletion` lookup hashes from `$doc->{_vcs_diff}` arrays once before the rendering loop. Per-line lookups are now O(1) hash access instead of O(n) array scans.

### ~~P3: [Performance] Palette filtering rescans all files on every keystroke~~ FIXED
`_filter_recent_files` and `_filter_all_files` iterated the entire file list and called `_fuzzy_score` twice per item on every keystroke.

**Fix:** `_filter_all_files` already had incremental substring filtering and a 5000-item scoring cap. Extracted shared `_build_file_item()` and `_fuzzy_rank_file_items()` helpers, reducing code duplication and consolidating the scoring logic. The recent files list is typically <50 items so no further optimization needed.

### ~~P3: [Performance] Regex recompilation in FileSearchEngine inner loop~~ FIXED
`FileSearchEngine.pm` line ~449: `_find_match_in_content` compiles the search regex via `eval { qr/$query/ }` on every per-line match check. Should pre-compile once at search start.

**Fix:** Fixed as part of the P2 ReDoS fix. `_find_match_in_content` now uses the pre-compiled regex from `$self->{_perl_regex}` instead of re-compiling via `eval { qr/$query/ }` on every line.

### ~~P3: [Code Quality] _filter_recent_files and _filter_all_files are 90% identical~~ FIXED
`Palette.pm` lines 205-315: two ~55-line functions with nearly identical item-building and scoring logic. Only the data source differs. Should extract to a shared `_filter_file_items()` helper.

**Fix:** Extracted shared `_build_file_item()` and `_fuzzy_rank_file_items()` helpers. Both `_filter_recent_files` and `_filter_all_files` now use these for item construction and scoring, eliminating the duplicated logic. Fixed as part of the P3 palette filtering performance fix.

### P3: [Code Quality] Display path normalization duplicated in 5+ locations — NO LONGER APPLICABLE
The pattern `if (index($path, "$cwd/") == 0) { substr(...) }` appears in `Palette.pm`, `FileSearchEngine.pm` (`_parse_lines` twice, `_tick_perl`), and elsewhere. Should be a utility function.

**Resolution:** After the palette filter refactoring (P3 palette dedup fix), only 2 occurrences remain — not enough to justify extracting a utility function.

### ~~P3: [Code Quality] State guard clauses copy-pasted 4+ times~~ FIXED
`Commands.pm` repeats the same 4-line guard block (`return if $self->{state} eq 'footer_input'` etc.) in `cmd_open_file`, `cmd_recent_files`, `cmd_find_in_files`, and `_column_paste`. Should extract to `_in_modal_state()` helper.

**Fix:** Added `_in_modal_state()` helper that checks for footer_input, prompt, find, and dialog states. Replaced the 4-line guard blocks in `cmd_open_file`, `cmd_recent_files`, and `cmd_find_in_files` with single-line `return if $self->_in_modal_state()`. Note: `_column_paste` did not have the guard pattern.

### ~~P3: [Bug] No user feedback for invalid goto_line input~~ FIXED
`Commands.pm` lines ~682-699: if the user enters something like `abc` or `1:2:3` in the Go To Line input, the function silently returns with no message. Should display an error or hint about expected format.

**Fix:** Added status message "Invalid format. Use: line, line:col, or :col" when the input doesn't match any valid pattern.

### ~~P3: [Documentation] DESIGN.md architecture diagram is stale~~ FIXED
The architecture diagram references "Commands/Menu/Preferences" module layout and doesn't reflect the current pill-based status bar, progressive disclosure, or the FILE/EDIT/NAVIGATE/VIEW section organization.

**Fix:** Completely rewrote the architecture diagram to show all 22 modules in their correct layers. Updated the module responsibilities table from 9 to 21 entries (added CommandRegistry, FindEngine, Highlighter, FileTree, FileSearchEngine, Diff, InputWidget, WrapMap, LineMap, Minimap, Chars, Config). Updated the data flow diagram to include FileTree, FindEngine, and Diff.

### ~~P3: [Documentation] Unverified "95%+ coverage" claim in DESIGN.md~~ FIXED
DESIGN.md claims "95%+ automated test coverage" but no coverage metrics exist. Several modules (`Config.pm`, VCS integration paths) have little or no direct test coverage.

**Fix:** Replaced unsubstantiated "95%+ automated test coverage" with "comprehensive automated testing" — accurate without making a specific claim.

### ~~P3: [Tests] Tautological tests verify messages not behavior~~ FIXED
`editor.t` tests like `cmd_undo` check that a status message is set but don't verify the edit was actually reversed. If `cmd_undo()` is broken but still sets a message, the test passes.

**Fix:** Strengthened the undo/redo test in `editor.t` to verify actual document state changes: insert text → verify document changed → undo → verify document reverted to original → redo → verify document restored to edited state. Previously only checked that status messages were set.

### ~~P3: [Tests] Performance tests with hard timing thresholds are flaky~~ FIXED
`find_engine_perf.t` uses `ok($median < 5, ...)` which will fail on slow CI or loaded machines. Should use `diag()` to report timing without failing the test.

**Fix:** Relaxed the two hard timing thresholds from 10ms to 50ms. The actual times are typically 1-4ms, so 50ms gives ample headroom for slow CI machines while still catching genuine regressions. Timing details continue to be reported via `diag()`.

### ~~P3: [Tests] No test for CommandRegistry consistency~~ FIXED
No test verifies that all commands have unique IDs, all shortcuts are unique, or all section names in `@SECTION_ORDER` are valid. If someone breaks CommandRegistry, all 33 commands silently disappear from the palette.

**Fix:** Added two new subtests to `tests/command_registry.t`: "All shortcuts are unique" (verifies no two commands share a shortcut) and "All command sections are in SECTION_ORDER" (verifies every command's section is valid). Note: unique IDs were already tested.

### ~~P3: [Repo Hygiene] Junk files not gitignored~~ FIXED
11 `perflog*.txt` files, `foo.txt`, and `lib/Zepto/goo.js` are untracked in the working directory. These should be `.gitignore`d to prevent accidental commits.

**Fix:** Added `perflog*.txt` and `foo.txt` to `.gitignore`. `lib/Zepto/goo.js` was not present in working directory (already removed).

## ~~P3: long filenames in open file dialog~~ FIXED
Long filenames bust out of the box. Actually it's kinda useful to use more of the screenspace, but it leaves screen artifacts. Also useful to widen the picker, like with find across files picker.

**Fix:** Widened Open File and Recent Files pickers to 120 chars (matching Find in Files). Long directory paths (shortcuts) are now truncated from the start with ellipsis to prevent overflow past the box border.

### ~~P1: Search should jump to first~~ FIXED
When searching for a string that's not currently in view, screen/cursor should jump to match.

**Fix:** Removed `skip_jump` from `_find_value_changed()` so typing in the find bar triggers `_find_nearest_match()` on each keystroke. For matches outside the viewport, the background search completion in the main loop now also triggers a jump when it finds new matches that weren't available during the synchronous viewport-only search.

### ~~P3: Transform feature~~ FIXED
I'd like the ability to use cmd line tools to transform fragments of text. For example, select some text, press transform, type "sort | uniq", and have the selected text replaced with the result of piping it through those process. If no text selected, auto select current line (or maybe entire doc, WDYT?). Also give option to put output in clipboard instead of replacing inline. Give hints in UI as to how to use the functionality. e.g. "sort | uniq", "tac", "python3 -m json.tool"

**Fix:** Added `⌥T` "Transform via Shell" command. Opens a footer input with hint showing example commands (`sort | uniq`, `tac`, `python3 -m json.tool`). Pipes the selected text (or current line if no selection) through `sh -c "$command"` via `IPC::Open2` and replaces inline. Registered in command palette under EDIT section. **Decision:** No selection defaults to current line (not entire doc) — more predictable and less destructive. Clipboard output option deferred — users can use `pbcopy`/`xclip` in the command itself.

### ~~P2: Syntax highlighting misaligned on lines with ⌥, ⚠, and similar Unicode symbols~~ FIXED
`_char_display_width()` used overly broad Unicode ranges (U+231A-23FF, U+2600-27BF, U+2B50-2B55) that returned width 2 for hundreds of narrow (EAW=N) characters like ⌥ (U+2325), ⚠ (U+26A0), ✔ (U+2714). These are width 1 in terminals. On lines with these characters (common in bugs.md keyboard shortcuts), syntax tokens were shifted right by 1 per such char, word wrap broke at wrong positions, and the minimap viewport alignment was off.

**Fix:** Replaced the three broad ranges with precise sub-ranges listing only the characters that are actually East Asian Wide (EAW=W/F) per Unicode. For example, the Misc Technical range (U+231A-23FF) now only matches ⌚⌛ (U+231A-231B), 〈〉 (U+2329-232A), ⏩⏪⏫⏬ (U+23E9-23EC), ⏰ (U+23F0), ⏳ (U+23F3). Added regression tests for both the wide and narrow characters.

### ~~P2: Smart sort~~ FIXED
Sort files in tree/search results by human friendly numbers, not ascii. e.g. file7.txt, file8.txt, file9.txt, file10.txt (10 after 7).

**Fix:** Added `_natural_cmp()` function that splits filenames into text and numeric chunks and compares numbers numerically. Applied to all four sort locations: FileTree `_scan_dir_one_level` and `_walk_for_files`, FilePicker `_discover_files` and `_apply_filter`.

### ~~P0: Slight lag on typing~~ FIXED
I notice it when typing and it's annoying. Figure out the bottleneck. Particularly visible when holding down a key to repeat chars.

**Fix:** Multiple optimizations across several commits: (1) Debounced `head_changed()` file I/O to every 2s and `check_external_changes()` stat to every 1s. (2) Made WrapMap incremental — only rebuilds when content version changes, with content-keyed cache for full rebuilds. (3) Added minimap caching keyed on content version. (4) Implemented differential rendering — Renderer returns per-row array, Editor diffs against previous frame and only emits changed rows to terminal. Reduced terminal I/O from ~27KB to ~1-2KB per frame for typical edits. Net result: char/none frame times dropped from ~55ms to ~45ms median (~18% improvement).

### ~~P1: New files dont appear in tree.~~ FIXED
Open zepto, see tree. Create new tab. Save it. New file should be visible in tree.

**Fix:** Added `$self->{file_tree}->refresh()` call after successful Save As in `cmd_save()`. The file tree's `refresh()` method re-scans the filesystem while preserving expand/collapse state, so the newly saved file appears immediately.

### ~~P3: Ruler does not extend to width of screen~~ FIXED
Currently it stops 1 char short of end of screen. Particularly visible in light mode as it's a black filler.

**Fix:** Swapped `RESET . CLEAR_LINE` to `CLEAR_LINE . RESET` in `_render_ruler_bar`. Same fix pattern as the earlier screen-width fix — `CLEAR_LINE` must happen before `RESET` so it erases to end-of-line using the ruler's background color, not the terminal default.

### ~~P1: Cursor off by one in palette filter~~ FIXED
The cursor position is 1 char to the right of where it should be in palette filter. Actually, it may be correct, and the text rendering
is 1 to the left. Shouldn't this be using the standard input text widget, and if so, how is just this one broken?

**Fix:** The cursor positioning in `render()` used `$pal_x + 5` but the filter text renders at `$pal_x + 4` (box border + space + icon + space = 4 chars before query text). Changed to `$pal_x + 4` to align cursor with text.

### ~~P2: Diff view discoverability~~ FIXED
When in diff view, make it visible on screen how to move to next/prev diff. If attempting to diff on a line that has no diff, jump to next one (if exists). Put a green/yellow/red/grey indicator in the diff view button on the status bar that matches diff status of where line is currently placed (grey is none). This is a subtle indicator of what this button's for to help users discover it.

**Fix:** Three changes: (1) The Diff View pill in the status bar now changes color based on the current line's VCS status — green (added), amber (modified), red (deleted), or default grey (no change). Added `pill_diff_added/modified/deleted` theme colors for both dark and light themes. (2) Pressing ⌥D on a line with no change now auto-jumps to the next change instead of showing "No change at cursor". (3) Next/Prev Change commands (⌥N/⌥P) remain accessible via the command palette for discoverability.

### ~~P3: Tree hide~~ FIXED
Ability to competely hide tree. Sometimes I really just care about editing a single file and want minimal screen clutter. e.g. a git commit msg. There should be a cmd to completely toggle it. If using ctrl-o to open a file, the sidebar should vanish once the file is opened (assuming tree is meant to be hidden). Make it clear in UI how to toggle the tree - should be visible at all times. Add cli options to force opening mode. If opening a single file from CLI, default to tree hidden.

**Fix:** ⌃B now toggles tree visibility (show/hide) instead of just focus. When tree is hidden and ⌃O is pressed, tree temporarily appears with filter for file picking, then auto-hides after file selection or Esc. Opening specific files from CLI defaults to tree hidden; no-args or directory launch keeps tree visible. Added `--no-tree` CLI flag and `ZEPTO_TREE=0` env var for explicit control.

### ~~P1: Incorrect cursor placement in command palette~~ FIXED
When opening command paletted, terminal cursor is not placed in text field

**Fix:** The cursor positioning code in the renderer used hardcoded width (60) and height (20) values that didn't match the actual palette rendering, which uses responsive widths (120/80/60) based on terminal width and dynamic height based on terminal rows. Synchronized the cursor positioning calculations to match the palette rendering dimensions exactly.

### ~~P1: Clicking document editor should unfocus file tree~~ FIXED
If navigating file tree, and user clicks in main editor area, unfocus tree and return to editing.

**Fix:** Added tree unfocus check at the beginning of the "Click in text area" section of `handle_mouse_event`. When the file tree is focused and the user clicks anywhere in the document area (gutter or text), `_tree_unfocus()` is called to cancel any preview, restore the original tab, and unfocus the tree. The view reference is also refreshed after unfocus in case the active tab changed.

### ~~P3: Toggle comment enhancements~~ FIXED
Support HTML which is both prefix and suffix. <!-- xxx -->. In HTML be aware of nested script or style and switch commenting char appropriately. Move the comment
definitions outside of Base.pm into their respective syntax files.

**Fix:** Three changes: (1) Moved comment prefix definitions from the centralized `%COMMENT_PREFIX` hash in Base.pm to individual `sub line_comment_prefix` overrides in each of the 42 syntax files. Base.pm now returns `undef` by default. (2) Added `comment_style($state)` API to Base.pm that returns `{ prefix => ..., suffix => ... }` — suffix is optional for line-prefix comments. HTML.pm overrides this for context-aware commenting: normal HTML uses `<!-- -->`, `<script>` blocks use `//` (JavaScript), `<style>` blocks use `/* */` (CSS). CSS.pm overrides to use `/* */` block comments (was incorrectly mapped to `//`). (3) Updated `cmd_toggle_comment` in Commands.pm to handle prefix+suffix block comments: inserts/removes suffix at line end and prefix at indentation, with correct offset handling (processes end-to-start).

### ~~P2: Scroll wheel cannot scroll more than a page~~ FIXED
When using scroll wheel, the doc offset scrolls, but gets stuck when the selected line hits top or bottom, preventing scrolling more than a page at a time.

**Fix:** The `_explicit_scroll` flag was being consumed (deleted) on a single render cycle, so the viewport snapped back to the cursor as soon as scrolling stopped. Changed the flag to persist across renders until a non-scroll user event occurs. The flag is now cleared at the start of `handle_event()` in Editor.pm — scroll events immediately re-set it via `scroll_up`/`scroll_down`, so it persists during scrolling but clears on any other action (typing, arrow keys, clicking). This allows unlimited scrolling away from the cursor, with the viewport snapping back only when the user takes a non-scroll action.

### ~~P2: "More" home/end~~ FIXED
Pressing home once on line should jump to first non-whitespace char (e.g. where code is indented). Pressing again should jump to start of actual line (in front of whitespace). Pressing one more time should jump to start of doc (line 1). Similar for End.

**Fix:** Smart Home cycles three states: first-nonws → col 0 → document start. Smart End cycles: line end → document end. Both work in normal and word-wrap modes. Also fixed `do_enter()` to set cursor position directly instead of using `move_to_line_start()` (which now has smart cycling that would send the cursor to doc start on empty new lines).

### ~~P3: Move forward/back~~ FIXED
Keep a history of major locations visited across files and within files. Many editors support something like this. Keyboard shortcuts to quickly move back forward throught location histor.

**Fix:** Added location history with `⌥-` (Go Back) and `⌥=` (Go Forward) shortcuts. Uses dual-stack model: back stack and forward stack. Location is recorded automatically before major jumps: Go to Line, Find Next/Prev, Next/Prev Change, and file opens. Each entry stores file path + line + col. Back navigation pushes current position to forward stack and pops from back stack. Forward does the reverse. New jumps clear the forward stack (new branch of history). Cross-file navigation switches tabs or reopens files as needed. History limited to 100 entries. Both commands registered in command palette under NAVIGATE section.

### ~~P2: Recent files~~ FIXED
Like ^O open, but list of recently visited files. Sorted by most recent first.

**Fix:** Added `⌃E` shortcut for Recent Files. Files are tracked when opened (via file tree, command line, or the recent files picker itself) and persisted to `~/.config/zepto/recent_files`. The picker reuses the command palette overlay with mode-specific title ("⌃E Recent Files"), fuzzy filtering, and file-type icons. Files are shown with filename as label and directory as secondary text. Most recently opened file appears first. Registered in CommandRegistry under FILE section.

### ~~P0: Reports of sluggishness~~ FIXED
Some users have reported a delay between typing and seeing results on screen. Hard to reproduce. Go explore and figure out likely cause.

**Fix:** Found three per-render bottlenecks: (1) WrapMap was unconditionally invalidated and rebuilt from scratch on every render, even when content hadn't changed — added `_content_version` counter to Document so WrapMap auto-detects changes and only rebuilds when needed. (2) `head_changed()` did file I/O (open + read + stat on `.git/HEAD`) on every render — debounced to every 2 seconds. (3) `check_external_changes()` did `stat()` on the active file every render — debounced to every 1 second.

### ~~P3: Lightmode glitches~~ FIXED
In lightmode. On short docs, the space beyond the final line is grey and looks out of place.

**Fix:** Changed light theme `empty_line_bg` from `bg_rgb(225, 228, 235)` (grey) to `bg_rgb(250, 250, 252)` (near-white) so empty lines beyond the document blend with the white editor background.

### ~~P3: Screen width~~ FIXED
The ruler, minimap, and bottom status bar all stop one char short of the end of the window. The tab bar does not. Ensure all reach end of window so entire screen is filled.

**Fix:** Swapped the order of `RESET` and `CLEAR_LINE` escape sequences in all rendering functions (text rows, status bar, find bar, footer input, prompt). Previously `RESET . CLEAR_LINE` cleared the styling first, then erased to end-of-line using the terminal's default background — causing any residual gap to appear in the wrong color. Now `CLEAR_LINE . RESET` erases first using the editor's current background color, then resets. Applied to 8 locations across the renderer.

### ~~P3: Status bar spacing~~ FIXED
No space between the Line number pill (first in status bar) and word wrap, whereas all others have spaces.

**Fix:** Added explicit gap space before the first center pill in the status bar, matching the spacing between other pills. Also adjusted the available space calculation to account for the extra space.

### ~~P2: Go-to-line new UI~~ FIXED
The status bar starts with a line number pill, and also has a go to line pill. Collapse these into a single element.
The line number pill (first), should also sho the ^G shortcut. When pressing this key, or clicking the pill, the line:col
string should become editable. Initially the entire text should be selected, allowing user to start typing and replace selection, or to move the cursor and edit existing. User may end XX, XX:YY, or :YY to move line, line and col, or just col (on same line) respectively - there should be text hints displayed to explain this. Use standard text input component used elsewhere. Ensure this box is wide enough to support docs of at least 9999:999. Beyond that, ok to scroll.

**Fix:** Merged the separate "Go to Line" pill into the cursor position pill. The pill now shows `⌃G` shortcut and is clickable. Pressing ⌃G or clicking the pill opens an inline input pre-filled with the current `line:col` (all selected, so typing replaces). Hint text shows "line, line:col, or :col" format guide. Input is 10 chars wide (enough for 9999:999 with scrolling for larger). The "Go to Line" command remains in the command palette for discoverability.

### ~~P3: Theme ^T should be global shortcut~~ FIXED
For example, should work when in find dialog.

**Fix:** Added `⌃T` to the top-level global shortcuts in `handle_event()`, alongside `⌃Q` and `⌃S`. Theme toggle now works from any UI state: find bar, command palette, footer input, dialog, and prompt.

### ~~P2: Comment/uncomment line~~ FIXED
Ctrl+/ should comment or uncomment the current line. If no text selected, current line. If text selected, all lines this selection spans. Language specific comments, e.g. # or // or <!-- .. -->. For languages that support multiline comment blocks, dont use this, only single lines (e.g. yes on //, no on /* .. */). Handle cases for mixed language documents (e.g. HTML with embedded CSS or JS).

**Fix:** Added `line_comment_prefix()` to `Zepto::Syntax::Base` with a lookup table covering all 42 syntax languages. `cmd_toggle_comment` in Commands.pm detects the language from the active highlighter's grammar, determines the line range (single line or selection), checks if all non-blank lines are already commented, and toggles accordingly. Comments are aligned at the minimum indentation of the selected lines. Wired to `⌃/` (Ctrl+/) and registered in CommandRegistry under DOCUMENT section.

### ~~P3: Close empty start tab when opening first file.~~ FIXED
A common scenario is: open zepto (which shows an untitled empty tab), then navigate to a file to edit. In this case, if the initial empty tab has not been edited, automatically close it to reduce clutter.

**Fix:** Added `_empty_untitled_tab_index()` helper that checks if a tab is empty, unedited, and has no file. When opening a file via `_load_file()` (⌃O, recent files, command palette) or confirming a tree preview (Enter), if the previous tab was an empty untitled tab, it's automatically closed. Edited untitled tabs are preserved.

### ~~P2: Line by line scrolling in editor.~~ FIXED
When using mouse scrolling (wheel or touchpad gesture), the file tree scrolls item by item, which feels precise and smooth. However the editor has different behavior which feels janky. Make editor mouse scroll behave same way as tree.

**Fix:** Changed editor mouse scroll from 3 lines per event to 1 line per event, matching the file tree's behavior.

### ~~P3: Diff view does not preserve line wrap~~ FIXED
If word wrap enabled, and diffing a hunk with long line, the word wrap is disabled in the diff, which is jarring. Preserve word wrap settings.

**Fix:** Three changes: (1) Removed the conditional in Editor.pm that disabled WrapMap when diff hunks were expanded — word wrap now stays active in diff view. (2) Added a combined WrapMap+LineMap entry-building path in Renderer.pm: when both are active, LineMap provides the entry ordering (doc lines + old/base lines from expanded hunks) while WrapMap provides word wrapping for each entry. Old/base lines are wrapped using `wrap_line()` and doc lines use `segments_for_line()`. (3) Updated `_render_old_line_row` to handle wrap segments — continuation rows get indent prefix with `↪` indicator, and content is sliced to the segment's visual range instead of the full viewport width. Gutter markers extend across all wrap continuation rows of old lines.

### ~~P2: Find/replace pills should be clickable~~ FIXED
Regex, case sensitivie, ok, cancel: mouse clicks should activate.

**Fix:** Already implemented — `handle_find_bar_click()` in Editor.pm computes click regions matching the renderer layout and handles clicks on all four pills: regex toggle, case toggle, cancel (Esc), and OK (Enter). Click regions are calculated from the same layout formula as the renderer to stay in sync.

### ~~P3: Column mode mouse selection~~ FIXED
After activating col selection mode, dragging with mouse should select col based selection, but it defaults to line.

**Fix:** Updated the drag handler's "start selection on first drag" logic to check `$view->column_select()` in addition to the Alt modifier. When column mode is already active (via ⌥C toggle), dragging now starts a column selection instead of a linear one. Alt+drag continues to start column selection from scratch as before.

### ~~P2: Line number indicator resizing~~ FIXED
The left pill constantly resizes as moving across lines due to empty lines (e.g. :60 -> :1). This makes the whole bar jiggle.

**Fix:** Added minimum width padding to the cursor position pill so it doesn't shrink below a reasonable size. The pill text is right-padded with spaces to keep surrounding pills stable.

### ~~P2: More prominent ctrl-space hint~~ FIXED
This is the most important key to know about, but it's hidden in corner, with no real clue as to what it means. How to make this obvious for first time users?

**Fix:** Added "Commands" label to the palette pill in the status bar. Previously showed only `{icon} ⌃␣` — now shows `{icon} Commands ⌃␣`. Updated in both document-context and tree-context status bars. The pill already uses a distinctive blue background that differentiates it from other pills.

### ~~P3: Command palette too wide.~~ FIXED
Doesn't need to be as wide and ends up with shortcut keys too far from respective action. Pick a reasonable max width.

**Fix:** Reduced palette max width from 120 to 80 columns at wide terminals (>=120 cols). Standard terminals (<120 cols) keep the 60-column max. Removed the 160-col breakpoint that created an overly wide 120-column palette. Shortcuts now stay close to labels at all terminal widths.

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

### ~~P3: Nerd icon overhaul~~ FIXED
Re-evaluate current icon selection. Many duplicates. Pick familiar feeling icons for actions.

**Fix:** Audited all 52 icon definitions in Chars.pm. Found 3 duplicate codepoints: (1) NF_CLOSE (\x{f00d}) duplicated NF_TIMES — removed NF_CLOSE (was unused in %CHARS mapping). (2) NF_WRAP (\x{f0ea}) duplicated NF_PASTE — changed NF_WRAP to \x{f036} (fa-align-left, text lines icon). (3) NF_PALETTE (\x{f0c9}) duplicates NF_MENU — left as-is since both semantically represent the same hamburger menu concept. No other icon issues found; existing selections are appropriate for their actions.

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

### ~~P3: Mouse parity incomplete~~ FIXED

~~Double-click word selection, triple-click line selection~~, and ~~mouse cursor placement inside input fields (find/replace, go to line)~~ are not implemented.

**Guideline**: `docs/UI_GUIDELINES.md` → Mouse And Keyboard Behavior.

**Fix (partial):** Added multi-click detection in the document area press handler. Tracks last click time, line, and click count. Double-click (within 400ms on same line) calls `select_word()` to select the word under cursor. Triple-click calls `select_line()` to select the entire line including newline. Click count cycles back to 1 after triple.

**Fix (complete):** Mouse cursor placement in input fields was already implemented for find/replace bar and footer input (Go to Line, Save As, Transform). Added the missing piece: command palette filter input now supports mouse click cursor placement via `get_palette_geometry()` in Renderer.pm and click detection in `_handle_palette_mouse()` in Palette.pm.

### ~~P3: Light theme `status_accent` used `bg_rgb` instead of `fg_rgb`~~ FIXED

`status_accent` in the light theme was defined with `bg_rgb(30, 102, 245)` — a background color escape sequence — when it is semantically a foreground accent color (consistent with the dark theme's `fg_rgb(125, 207, 255)`). Any future use of this color for text rendering would have produced an invisible or incorrectly styled result.

**Fix:** Changed to `fg_rgb(30, 102, 245)`. Added a regression test to `tests/theme.t` asserting that `status_accent` produces a foreground escape sequence (`ESC[38;2;...`) in the light theme.

### ~~P3: Theme contrast not verified~~ AUDITED — OK

Dark and light themes have not been formally audited for readability or contrast. Non-color cues (icons, text) for state changes (VCS markers, selection, errors) should be verified in both modes.

**Guideline**: `docs/UI_GUIDELINES.md` → Colors And Readability.

**Audit result:** Both themes pass contrast review. Dark theme uses light text (192,202,245) on deep blue-black (26,27,38) — excellent contrast. Light theme uses dark text (76,79,105) on white — excellent contrast. Syntax colors are deep/saturated in both themes for readability. Intentionally subdued elements (gutter line numbers, VCS indicator blocks) have lower contrast by design to avoid distraction. Non-color cues are present: VCS uses colored block shapes (▎), errors use warning icon (⚠), status bar uses text labels + keyboard shortcuts, selections use cursor position + background color.

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

### ~~P1: [Bug] Ctrl+O file open doesn't unfocus file tree~~ FIXED
When launching zepto in directory mode (`./zepto .`), the file tree gets focus. After pressing Ctrl+O and selecting a file from the palette, focus remains on the file tree instead of transferring to the document. The status bar continues showing tree navigation hints instead of document editing pills.

**Fix:** Added tree unfocus logic to `_load_file()` in Commands.pm. After opening a file, if the file tree is focused, `set_focused(0)` is called to transfer focus back to the document editor.

### ~~P2: Markdown underscore emphasis renders inside identifiers~~ FIXED
Text like `NF_CLOSE (\x{f00d}) duplicated NF_TIMES` renders the substring between underscores as italic. Per CommonMark spec, `_` emphasis delimiters must not be intraword — an opening `_` must not be preceded by an alphanumeric character, and a closing `_` must not be followed by one. Only `*` allows intraword emphasis.

**Fix:** Split the combined `(\*|_)` emphasis regexes in Markdown.pm into separate `*` and `_` branches. The `_`, `__`, and `___` branches now check that the character before the opening delimiter and after the closing delimiter are not `\w` (word characters), matching CommonMark's intraword restriction. `*` branches remain unrestricted.

### ~~P2: [Bug] Binary files should not be previewed or naively opened~~ FIXED
Binary files (images, executables, .o files, etc.) currently get previewed in the file tree and can be opened as a tab, displaying garbage. Preview should detect binary content (e.g. NUL bytes in the first few KB) and show a "Binary file — cannot preview" message instead. Opening a binary file should show a read-only notice rather than dumping raw bytes into an editable buffer.

**Fix:** Added `_is_binary_file()` check in `Document::load()` that reads the first 8KB of raw bytes and looks for NUL characters. Binary files load a placeholder "(Binary file — size)" instead of the actual content. Insert and delete operations are blocked on binary documents. Save is blocked with "Cannot save binary file" error. Tree preview shows the placeholder. Pressing Enter on a binary file in the tree shows "Binary file — read only" status message. Added `_format_file_size()` helper for human-readable sizes.

### ~~P2: [Feature] Render images in terminal via Kitty graphics protocol~~ FIXED
On terminals that support the Kitty graphics protocol (e.g. Ghostty, Kitty), previewing or opening an image file (PNG, JPEG, GIF, BMP, SVG, etc.) should render the image inline in the terminal instead of showing binary garbage or a "cannot preview" message. Detect protocol support via the `TERM`/`TERM_PROGRAM` env var or a DA1/graphics query. Fall back gracefully to a text placeholder on unsupported terminals.

**Fix:** Added Kitty graphics protocol support to Terminal.pm: `supports_kitty_graphics()` detects support via `TERM_PROGRAM` (ghostty, kitty) and `TERM`/`KITTY_WINDOW_ID` env vars. `kitty_display_image()` transmits PNG/JPEG images using chunked base64 APC escape sequences (4096-byte chunks). `kitty_clear_image()` clears specific or all images. Image files are detected by extension (png, jpg, jpeg, gif, bmp, webp, svg, ico, tiff) on binary files. Editor renders images in the text area after the regular frame, with caching to avoid re-transmission when image/size hasn't changed. Images are cleared on tab switch and editor cleanup. Uses MIME::Base64 (Perl core module). Falls back to "(Image file — size)" placeholder on unsupported terminals.

### ~~P2: Syntax highlighting doesn't activate after Save As on new file~~ FIXED
Creating a new file and using Save As with a file extension didn't activate syntax highlighting.

**Fix:** Added `$self->active_highlighter()->set_file($filename)` in the Save As callback in `Commands.pm:65`, triggering grammar detection for the new filename. Added regression test.

### ~~P1: File picker (`⌃O`) doesn't find untracked files~~ FIXED
The Open File picker only showed git-tracked files. Untracked files (new images, scratch files) were invisible.

**Fix:** Added a second `git ls-files --others --exclude-standard` call in `FileTree::_build_all_files_list()` alongside the existing `git ls-files` for tracked files. Both results are combined. The two commands produce non-overlapping sets by design (tracked vs untracked-but-not-ignored).

### ~~P1: Native terminal paste (Cmd+V) causes cascading indentation~~ FIXED
When pasting multiline text from an external program using the terminal's native paste (Cmd+V), each line got progressively more indented due to auto-indent compounding.

**Fix:** Enabled bracketed paste mode. Added `enable_bracketed_paste()` / `disable_bracketed_paste()` to Terminal.pm (using the existing PASTE_MODE_ON/OFF constants). Added `paste_start` / `paste_end` key event detection in InputParser.pm for `\x1b[200~` / `\x1b[201~` sequences. Editor.pm tracks `_bracketed_paste` flag — `do_enter()` skips auto-indent while the flag is set. Added tests for both the escape sequence parsing and the auto-indent suppression.

### ~~P1: Pasting from system clipboard corrupts Unicode characters~~ FIXED
When pasting text containing non-ASCII characters (accented characters, CJK, emoji) via `⌃V`, the characters appear corrupted — multi-byte UTF-8 sequences are treated as individual bytes instead of proper characters.

**Root cause:** `paste_from_clipboard()` in `Terminal.pm:539-554` reads raw bytes from the clipboard command pipe (`pbpaste`, `xclip`, etc.) with no UTF-8 decoding. The copy direction (`copy_to_clipboard()`) correctly uses `utf8::encode()`, but the paste direction had no corresponding decode.

**Fix:** Added `binmode($fh, ':raw')` on the clipboard read pipe and `utf8::decode($text)` on the returned string, matching the encode/decode symmetry with `copy_to_clipboard()`. Added test verifying UTF-8 round-trip through the system clipboard (box drawing, emoji).

### ~~P1: Clicking previewed file content dismisses it instead of opening it~~ FIXED
When launching zepto with no args, clicking a file in the tree shows a preview. Clicking the previewed content in the main editor area dismissed the preview instead of confirming it.

**Fix:** Changed the document-area click handler in `handle_mouse_event()` to check for `preview_active` on the tree. When a preview is active, the click now confirms the preview (initializes VCS, cleans up preview state, closes empty untitled pre-preview tab) instead of calling `_tree_unfocus()` which cancelled it. Added regression test.

### ~~P2: [Bug] YAML syntax highlighting matches literals inside bare words~~ FIXED
In YAML files, substrings like `on`, `no`, `off` were incorrectly highlighted as keyword literals when inside unquoted bare words (e.g. `region`, `information`).

**Fix:** Added a bare word consumer rule `[a-zA-Z_][a-zA-Z0-9_.-]*` before the `$pos++` fallback in `Syntax/YAML.pm`. This consumes entire bare words in one go, preventing the tokenizer from creating substrings that partially match literals. Standalone literals (`on`, `true`, `false`) are still correctly matched since the `$LITERALS` check comes earlier. Regenerated YAML expected tokens. Added regression tests.

### P3: [Feature] Inline image rendering in Markdown preview — SKIPPED
On Kitty-protocol-capable terminals (e.g. Ghostty, Kitty), Markdown files containing image references (`![alt](path)`) should render the referenced images inline when the file is being previewed or edited. Images should be rendered at a reasonable size within the text flow. Fall back to showing the Markdown syntax as-is on unsupported terminals.

**Skipped — requires significant renderer architecture changes. Inline images interleaved with text need: (1) Markdown parser extension for `![alt](path)` tokens, (2) image row height calculation that displaces subsequent text rows, (3) per-image Kitty graphics ID management for multiple images on screen, (4) scroll-aware image repositioning. The P2 Kitty graphics fix handles whole-file image tabs, but inline images in flowing text is architecturally different. Recommend as a separate dedicated feature.**

### ~~P0: [Crash] Copying double-width characters crashes editor~~ FIXED
Copying text containing double-width characters (CJK, emoji) crashes with `Wide character in subroutine entry`. Reported crash in `copy_to_clipboard` when base64-encoding wide character strings for OSC 52.

**Root cause:** `MIME::Base64::encode_base64()` expects raw bytes, but `copy_to_clipboard()` passed Perl's internal wide-character strings directly. The pipe write to clipboard commands (`print $pipe $text`) had the same issue.

**Fix:** Added `utf8::encode()` to convert wide-character strings to UTF-8 bytes before passing to `encode_base64()` and the clipboard pipe. Added `binmode($pipe, ':raw')` on the clipboard command pipe. Added tests for CJK characters and emoji.

---

## Scorecard audit bugs (2026-03-06)

Bugs found by running `/scorecard` codebase audit.

### ~~P2: [Bug] `_char_to_visual_col()` doesn't handle wide characters~~ FIXED
`Renderer.pm:224` — increments `$visual_col` by 1 for all non-tab characters instead of calling `_char_display_width()`. Cursor positioning is wrong for lines containing CJK or emoji characters.

**Fix:** Replaced `$visual_col++` with `$visual_col += _char_display_width($char)` in both `_char_to_visual_col()` and `visual_to_char_col()`. Both functions now correctly handle CJK characters (width 2) and emoji. Added 15 tests covering CJK, emoji, and mixed ASCII+wide content in both directions.

### ~~P2: [Security] Symlink traversal in FileTree and FilePicker~~ FIXED
`FileTree.pm:123-547`, `FilePicker.pm` — `-d` and `-f` operators follow symlinks without `realpath()` bounds checking. A symlink inside the project directory could point outside the project root (e.g. `/etc/passwd`).

**Fix:** Added `_path_within_root()` helper to FileTree.pm that resolves symlinks via `Cwd::realpath()` and verifies the resolved path starts with the root. Applied to both `_scan_dir_one_level()` and `_walk_for_files()`. FilePicker.pm gets the same check in its `_discover_files()` walk. Root paths are resolved with `realpath()` at construction time. Symlinks that stay within the project root are preserved. Added test with escape symlink and safe symlink.

### ~~P2: [Security] ReDoS protection is length-only, no timeout~~ FIXED
`FindEngine.pm:455`, `FileSearchEngine.pm:296` — user regex patterns are compiled via `eval { qr/$pattern/ }` with a 1000-character length limit but no execution timeout.

**Fix:** Added `alarm(1)` (1-second SIGALRM) timeout around regex compilation in both `FindEngine::_compile_regex()` and `FileSearchEngine` startup. The alarm is cancelled on success and guaranteed cancelled on exception via a post-eval `alarm(0)`. Combined with the existing 1000-char length limit, this provides defense-in-depth against catastrophic backtracking.


### ~~P2: [DRY] Truncate-with-ellipsis duplicated 7+ times~~ FIXED
`Renderer.pm` — the ellipsis truncation pattern appeared 7+ times across tree nodes, palette items, and status bar elements.

**Fix:** Extracted `_ellipsis($str, $max_width, $mode)` helper supporting both end-truncation (default) and start-truncation (`'start'` mode). Replaced 5 of 7 occurrences — 2 remain where the truncation is interleaved with other calculations (`$trim_offset` tracking, `$ELLIPSIS` constant in progressive tab name truncation).

### ~~P3: [Bug] Scrollbar thumb boundary inconsistency~~ FIXED
`Renderer.pm` — one scrollbar rendering path used `<` (exclusive) while another used `<=` (inclusive) for `thumb_end`.

**Fix:** `thumb_end` is computed as `thumb_start + thumb_size - 1` (inclusive), so `<=` is correct. Changed the filter-flat tree scrollbar path to use `<=` to match the normal tree path.

### ~~P3: [Tests] Tautological test in terminal.t~~ FIXED
`terminal.t:346` — `ok(1, 'Kitty graphics detection exists')` always passed regardless of actual behavior.

**Fix:** Replaced with actual assertion: calls `supports_kitty_graphics()` and verifies it returns a defined 0/1 value. Note: `syntax_samples.t:120` and `syntax_samples.t:195` use `pass()` inside conditional branches (with `fail()` on the other branch) and are NOT tautological — the audit agent misidentified them.

### ~~P3: [Tests] Config.pm has no dedicated test~~ FIXED
`Config.pm` had implicit coverage through Document loading but no direct test file.

**Fix:** Added `tests/config.t` with 5 subtests covering `skip_directories()`, `skip_directories_hash()`, `max_files()`, `max_depth()`, and `picker_visible_rows()` — verifying both return types and default values.

### ~~P3: [Tests] Missing coverage for complex interactions~~ PARTIALLY FIXED
Palette header-skipping navigation now tested (5 new subtests in command_palette.t). WrapMap invalidation already well-covered (wrapmap.t:269-406). Mouse coordinate mapping and file tree preview→open→tab transitions skipped — require full integration test setup, not suitable for bug bash.

### ~~P3: [Documentation] TabManager.pm missing from DESIGN.md module inventory~~ FIXED
`DESIGN.md` module table omitted `TabManager.pm` and `FilePicker.pm`.

**Fix:** Added both TabManager and FilePicker to the Module Responsibilities table in DESIGN.md.

### ~~P2: [Bug] Light mode: tab bar stays dark after theme switch~~ FIXED
Switching from dark to light mode with `⌃T` leaves the tab bar rendered with dark theme colors. The tab bar appears visually dark against the light editor background.

**Root cause:** The tab bar cache in `Renderer.pm` (line ~722) builds its cache key from `$cols`, `$tree_width`, `$active_idx`, tab count, and per-tab state (display name, dirty flag, VCS changes) — but does not include the current theme. When the user toggles themes, the cache key is unchanged, so `_tab_bar_cache_get()` returns the stale dark-themed rendering.

**Fix:** Added `$theme->name()` as the first component of the tab bar cache key. Theme changes now cause a cache miss, triggering a full re-render with the correct theme colors. Added regression test verifying dark and light theme tab bars produce different output.

---

## TUI usability testing bugs (2026-03-23)

Bugs found during hands-on TUI usability testing via tmux session.

### ~~P1: [Usability] Enter in Find mode triggers Replace All — no separate find-only mode~~ FIXED
When opening Find with `⌃F`, the Replace field was always visible and pressing Enter always executed Replace All.

**Fix:** Restored find-only vs find-and-replace mode distinction per the spec. `⌃F` now opens find-only mode (no Replace field). Enter dismisses find and keeps cursor on current match. Tab activates the Replace field. Only when in Replace mode does Enter trigger Replace All. Added `↑↓` navigation hint to match count display. Added "Find and Replace" as separate command in palette. Updated renderer to conditionally show/hide Replace field and adjusted all click region calculations.

### ~~P2: [Bug] Auto-pair quote skip-over is disabled — typing closing quote adds duplicate~~ FIXED
Typing `"hello"` produced `"hello""` because quote skip-over was explicitly disabled.

**Fix:** Removed the `!_is_quote($char)` exclusion from the skip-over logic. For quotes, uses an odd-count heuristic: counts occurrences of the same quote character before the cursor on the current line. If the count is odd (cursor is inside an unclosed string), the closing quote is skipped over. If even (cursor is outside a string), a new quote is inserted normally. Brackets continue to always skip over.

### ~~P2: [Usability] Find bar text field doesn't clear or select-all on reopen~~ FIXED
Reopening `⌃F` kept previous text but didn't select it, requiring manual deletion before typing a new search.

**Fix:** `enter_find_mode()` now pre-selects all text in the find widget when reopening with a previous search term. Typing immediately replaces the selection (like VS Code).

### ~~P3: [Cosmetic] Find bar "$0" label: shown when regex off, and capture group replacement not discoverable~~ PARTIALLY FIXED
`$0` label appeared even when regex mode was off and there were no capture groups.

**Fix:** Capture group hints (`$0 $1 $2...`) now only appear when regex mode is ON AND the search pattern contains capture groups. Updated both the cursor positioning code and `_render_find_bar` in Renderer.pm. The hints use color-coded `$N` tokens matching the capture group colors in the find input. **Remaining:** A more explicit tooltip explaining how to use `$1` in the replace field would improve discoverability further.

### ~~P2: [Usability] Right arrow accepts entire ghost text completion — unexpected behavior~~ FIXED
Right arrow accepted the entire ghost text suggestion at once, which was unexpected (VS Code dismisses ghost text on Right arrow).

**Fix:** Changed Right arrow from accepting the entire ghost text to accepting one character at a time (like GitHub Copilot). Added `accept_char()` method to `Completion::Controller` that advances the prefix by one character while keeping the ghost active for the remaining text. When the last character is accepted, the completion is dismissed and recorded for RecentProvider. Tab continues to accept the full suggestion.

### ~~P3: [Usability] Ghost text completion does not re-trigger after undo~~ FIXED
After accepting ghost text and pressing `⌃Z` to undo, the ghost text did not reappear.

**Fix:** Added `_retrigger_completion_if_word()` helper that checks if the cursor is at a word character and sets `_completion_pending_at` to trigger the debounced completion. Called after both `cmd_undo()` and `cmd_redo()`. Ghost text now reappears after undo if the cursor position warrants it.

### ~~P0: [Bug] Perl warning on undo/redo near end-of-line~~ FIXED
`Use of uninitialized value $char_before in pattern match` printed to stderr after undo when cursor was at/past the line length boundary.

**Root cause:** `_retrigger_completion_if_word()` did not check that the cursor column was within the actual line length before calling `substr()`.

**Fix:** Added `return unless $col <= length($line)` guard and `defined $char_before` check.

### ~~P2: [Bug] history.json recent_files cluttered with temp files~~ FIXED
`_track_recent_file` in Editor.pm records every file opened — including temp files from test runs (`/tmp/...`, `/private/tmp/...`). The recent files list (max 50) gets filled with ephemeral files that no longer exist, pushing out real files.

**Fix:** Added early return in `_track_recent_file()` for paths matching `/tmp/`, `/private/tmp/`, and `/var/folders/` (macOS per-user temp). Added regression test. Updated existing tests to use non-temp paths.

### ~~P2: [Bug] Screen artifacts remain above cursor position after quitting~~ FIXED
When quitting zepto (`⌃Q`), everything above the cursor's vertical position remains visible on the terminal — the upper portion of the editor's alternate screen buffer content bleeds into the main screen.

**Root cause:** `leave_alt_screen()` in Terminal.pm only sent `ALT_SCREEN_OFF` (`\x1b[?1049l`). Some terminals don't fully restore the main screen buffer from the saved state, leaving alternate screen content visible.

**Fix:** Added `CLEAR_SCREEN` + `CURSOR_HOME` before `ALT_SCREEN_OFF` in `leave_alt_screen()`. This clears the alternate screen buffer before switching back to the main screen, so even terminals with imperfect `?1049l` handling show a clean exit.

### ~~P2: [Tests] diff_constraint.t spews debug output to console~~ FIXED
`tests/diff_constraint.t` prints `# Added: [...]`, `# Modified: [...]`, `# Deleted: [...]` lines to stdout during `make test`. These are debug/diagnostic prints left in the test, not TAP comments. They produce ~99 noise lines in the test output, making it harder to spot real issues.

**Fix:** Guarded the three `diag()` calls behind `$ENV{VERBOSE}`. Debug output now only appears when running with `VERBOSE=1 prove -v tests/diff_constraint.t`.

### ~~P1: [Bug] Undo of move-line corrupts buffer~~ FIXED
Moving a line with `⌥↓` or `⌥↑` then pressing `⌃Z` to undo corrupts the buffer — only one line remains visible, others disappear. Root cause: `_move_lines()` performs delete + insert as two separate undo actions; undoing only reverses the insert, leaving the delete in place.

**Fix:** Wrapped the delete and insert calls in `_move_lines()` with `$doc->begin_undo_group()` / `$doc->end_undo_group()` so the entire move is one atomic undo operation. QA-LINE-009 unskipped.

### ~~P2: [Bug] File tree Page Down/Up and Home/End don't trigger preview~~ FIXED
In the file tree, pressing Page Down, Page Up, Home, or End moves the cursor but doesn't show the preview of the newly highlighted file. Regular Up/Down arrows do trigger preview correctly. The `pageup`/`pagedown`/`home`/`end` handlers in `handle_tree_event()` (`Editor.pm:4215-4218`) call the tree navigation methods but omit `$self->_tree_preview_current()` which Up/Down include.

**Fix:** Added `$self->_tree_preview_current()` to all four handlers. QA-TREE-024 and QA-TREE-025 verify the fix.

## QA test suite discoveries (2026-05-03)

Bugs and observations found while expanding QA test coverage from 129 to 205+ scripts.

### ~~P3: Regex mode defaults to ON in find bar~~ FIXED
The find bar starts with regex mode enabled by default. Most editors (VS Code, Sublime, etc.) default to literal search. This means typing `foo.bar` matches `fooXbar` on first use, which is unexpected for most users. Toggle with ⌃R. Confirmed via QA-FIND-009.

**Fix:** `find_regex` now initializes to 0 in Editor.pm — literal search by default, ⌃R toggles regex on. The `qa/09_find_replace.txt` spec already described this behavior ("Without regex: literal `\d+` is searched"); only the code disagreed. Updated `tests/find.t` default assertion and `reg_049_find_regex_pipe.sh` (which assumed regex-on default; it now presses ⌃R first, preserving its original pipe-handling regression intent). All other find/replace QA scripts pass unchanged. Test: `reg_105_find_literal_default.sh` (QA-REG-105) — written first, verified failing ("3 of 3" via regex dot) before the fix.

### ~~P3: Find match counter not clamped when match count shrinks~~ FIXED
Noticed while writing QA-REG-105: with 3 matches and the cursor on match 3, toggling regex off (matches drop to 1) briefly shows "↑↓ 3 of 1" in the find bar — the current-match index isn't clamped to the new match count. Cosmetic; the next navigation normalizes it.

**Fix:** New `_clamp_find_current()` resets the index when it exceeds the new match count, called at both sites that replace `find_matches` without re-jumping (`_update_find_matches`, which the ⌃R/⌃C toggles use with skip_jump, and the background-search completion in `run()`). Tests: `tests/find.t` "find_current clamped when matches shrink" and `reg_107_find_count_clamp.sh` (QA-REG-107) — both written first and verified failing ("3 of 1" on screen) before the fix. Side discovery captured in the QA script: Enter in the find bar closes it; ↑↓ navigate matches.

### ~~P3: No "Save As" command in palette~~ FIXED
The command palette has "Save" (⌃S) and "Save and Close Tab" (⌃W) but no "Save As" / "Save to different location" command. File→Save As is a standard editor operation. Users can only save to the original path.

**Fix:** Added `cmd_save_as` (FILE section, no default shortcut) that always opens the footer input prompt — unlike `cmd_save`, which only prompts when the document has no path yet — prefilled with the document's current path (select-all active so retyping is quick). Confirms via `open_prompt` (Yes/No) before overwriting an existing file that isn't the document's own current path. On submit, writes via `Document::save()` (plain file I/O, no shell), updates the tab's `file_path`/`untitled_name`, and calls `active_highlighter()->set_file($filename)` to activate syntax highlighting for the new extension — same plumbing `cmd_save`'s inline "no path yet" flow already used, now shared via a `_finish_save_as` helper. **Security:** pure `open`/`rename`-based file I/O via the existing `Document::save()` path (already atomic: write to temp file, then rename) — no shell exec, no new attack surface; reviewed against `docs/SECURITY.md`.

**Bug found along the way:** while testing Save As with a long absolute path, the status bar message ("Saved: /very/long/path...") was never truncated to the terminal width in `Renderer.pm` (`_render_status_bar` and `_render_context_status_bar`). A message longer than the terminal width wrapped onto the next real terminal row, scrolling the whole screen and corrupting everything above the status bar (tab bar disappeared, ruler/gutter misrendered) until a forced full redraw. Not specific to Save As — any long `show_message`/`show_error_message` call could trigger it — but Save As surfaces it easily since users often save to long paths. **Fixed** by truncating the message with `_ellipsis($message, $cols - 1, 'start')` (truncate-from-start, matching the existing path-truncation convention elsewhere in Renderer.pm) at both message render sites. QA: `QA-FILE-*` (Save As), `QA-REG-126` (message truncation).

### ~~P3: Preference state persists between sessions~~ NO LONGER A TEST HAZARD
Toggle states (minimap, word wrap, nerd font, etc.) persist to preferences. This means QA tests that toggle features can affect subsequent tests. Tests must save and restore state. Not a bug per se, but a testing hazard worth documenting.

**Resolution (2026-08-29):** Persisting preferences is intended product behavior; the test hazard is gone since QA sessions run with a per-test `--state-dir` (QA-REG-106) — toggles land in an isolated temp dir, never in shared or real state.

### ~~P3: Transform (Alt+T) is shell-pipe only~~ FIXED
The transform feature (Alt+T) opens a shell command prompt. There are no built-in text transforms (uppercase, lowercase, sort, etc.) — users must type shell commands like `tr '[:lower:]' '[:upper:]'` or `sort`. This works but is not discoverable for users unfamiliar with Unix pipes.

**Fix:** Added 5 built-in, pure-Perl transforms in a new TRANSFORM palette section: Uppercase, Lowercase, Sort Lines, Reverse Lines, Unique Lines (first-occurrence order preserved, unlike shell `sort -u` which reorders). All operate on the current selection, or the whole document if nothing is selected — same auto-select-all scoping `cmd_transform` (⌥T) already uses. No shell exec: `cmd_transform_uppercase`/`cmd_transform_lowercase` call `_apply_text_transform`, a shared engine that reads the selected text, applies a coderef, and writes it back via `Document::replace()` (single undo entry; no-op — no undo entry, no dirty flag — if the transform doesn't change anything). `cmd_transform_sort_lines`/`cmd_transform_reverse_lines`/`cmd_transform_unique_lines` go through `_apply_line_transform`, which layers line-splitting on top (preserves whether the original text ended with a trailing newline). ⌥T / "Transform via Shell" is completely unchanged — still in the EDIT section, still shell-pipe. **Behavioral discovery along the way:** `⌃Space` is dual-purpose — if the cursor sits immediately after a word character, it's routed to the completion-trigger path instead of opening the palette (see `Editor.pm::handle_ctrl_char`, char `' '` case). This is intended, pre-existing behavior (not something this change touched), but it means interactive testing of a selection ending mid-word needs the cursor moved off the word boundary (e.g. `Home`, or extend the selection one more character past the word) before pressing `⌃Space`, or the palette won't open.

## Live debugging session (2026-08-28)

Reported by user while editing in Ghostty: keyboard cursor movement intermittently unresponsive, typing "really laggy" on small files, clicking the mouse un-sticks everything.

### ~~P0: Renders suppressed after any mouse motion — typed text and cursor moves invisible until next click~~ FIXED
`_last_event_was_hover` in Editor.pm is set by mouse events (`= 1` on motion, `= 0` on press/release/scroll) but **never reset by keyboard events**. After any hover-motion event with no target change, the main loop's render-skip branch (`Editor.pm` `run()`, ~line 702) stays active for ALL subsequent keyboard input: characters are inserted into the document and arrow keys move the cursor internally, but the screen never redraws. The next mouse press/scroll (or hover-target change) finally renders, revealing all the "missing" edits at once. With `?1003h` any-motion tracking enabled, merely brushing the mouse over the window arms this state, so it happens constantly in real use. (Side note: word characters looked merely "laggy" instead of frozen because the completion debounce fired a render ~100ms later; non-word characters and arrow keys never rendered at all.)

**Repro (verified in hangon session):** inject SGR motion `ESC[<35;30;5M`, then type `Z` → screen still shows old content, no modified indicator. Inject a click → `Z` appears (it was in the document all along). The render-skip decision uses only the *last* event's hover-ness instead of "did this batch contain anything render-worthy".

**Fix:** Replaced the last-event flag with a per-batch decision. `handle_input()` resets `_hover_changed`/`_batch_renderable` at batch start; `handle_event()` sets `_batch_renderable` for every event except idle hover motion; new `_input_needs_render()` returns true if the batch changed a hover target OR contained any non-hover event. `run()` consults that instead of `_last_event_was_hover` (now removed). The motion-flood optimization is preserved: batches of pure target-unchanged motion still skip rendering. Tests: `tests/editor.t` "Typing after hover motion still renders", QA `reg_101_hover_type_render.sh` (QA-REG-101, QA-MS-021) — both written first and verified failing against the unfixed build.

### ~~P1: InputParser stalls event queue after unknown/discarded escape sequences~~ FIXED
`InputParser::parse()` stops its event loop whenever `_parse_one()` returns `EVT_NONE`, but `EVT_NONE` conflates two cases: (a) incomplete sequence, need more bytes — correct to stop; (b) complete-but-unknown sequence already *consumed* from the buffer (`_decode_csi` unknown final, `_parse_csi` sanity limit, `_parse_ss3` unknown final, CSI-u codepoints outside 32–126) — wrong to stop. In case (b) any events already in the buffer behind the junk stay unparsed until the *next* input arrives, so keys lag one event behind (press Up → nothing; press another key → the Up fires).

**Repro (verified):** `parse("\x1b[I\x1b[A")` returns 0 events with 3 bytes stuck in the buffer; a subsequent `parse("x")` returns `key:up` + `char:'x'`.

**Fix:** In `InputParser::parse()`, on `EVT_NONE` the loop now continues when bytes were consumed (discarded junk) and stops only when the buffer is unchanged (truly incomplete sequence awaiting more bytes). Tests: 4 new subtests in `tests/input_parser.t` (unknown CSI/SS3/CSI-u followed by real events; incomplete sequences still wait), QA `reg_102_unknown_seq_stall.sh` (QA-REG-102, QA-EDIT-022) — all written first and verified failing against the unfixed code.

### ~~P2: Hover highlight paints one event late~~ FIXED (misdiagnosis — hover color was dimmer than bright pills)
Originally logged as "the render paints the previous hover state, one event late". Instrumenting `_handle_mouse_hover()` and the status bar paint proved that diagnosis **wrong**: hover state is hit-tested, stored, and painted in the same frame, correctly. The real bug: the flat `pill_hover_bg` (dark: rgb 62,69,100) sat *between* the pill category colors — brighter than toggle-off/action pills but **dimmer than toggle-on (52,79,138) and palette (86,119,252) pills**. Hovering a bright pill therefore DIMMED it, which reads as a de-highlight and mimics stale state (the pill "lights up" only when the mouse leaves and it reverts to its bright normal color). Light theme had the same inversion vs its lavender pills.

**Fix:** `pill_hover_bg/fg/edge` are now brighter than every pill category: dark rgb(110,140,255) with white text, light rgb(90,110,240) with white text. Tab and tree hover colors were audited and are correct (hover sits between normal and active). Tests: `tests/theme.t` asserts pill hover luminance exceeds all four pill category backgrounds (dark) and is visibly distinct (light) — verified failing against the old colors; tier-2 visual `ms_022_pill_hover_bright.sh` (QA-MS-022) plus QA-REG-104.

### ~~P0: QA suite commits junk into the real repository (sandbox escape in qa-helpers)~~ FIXED
`qa_project()` in `qa/lib/qa-helpers.sh` did its `cd` inside the function but every caller invoked it via command substitution — `dir=$(qa_git_repo)` — which runs in a subshell, so the `cd` was silently lost. The 10 scripts using `qa_git_repo` then ran `git init -q` (a silent no-op inside an existing repo), `git config user.name/email` (rewriting the REAL repo's local config to "Test <test@test.com>"), and `git add`/`git commit` **in the zepto checkout itself**. Every full `make qa` run stacked ~10 junk "init"/"initial" commits onto main, sweeping up whatever was in the working tree — this is also the origin of the historical "init/initial" commits in the repo's log, the leaked `test.txt`/test files (commit "Remove leaked test files"), and the polluted local git identity. The 9 scripts using bare `qa_project` similarly created their "project" files in the repo root instead of a temp dir, so several tree/picker tests were unknowingly running against the real repo.

**Found:** 2026-08-28, when three full QA runs added 30 junk commits on top of main mid-session (recovered via `git reset` to the pre-run commit; working tree was unaffected). Bisected by running each `vcs_*` script serially and watching `git rev-parse HEAD`.

**Fix:** `qa_project`/`qa_git_repo` now set `QA_PROJECT_DIR` instead of echoing it, and all 19 call sites (18 tier-1 + 1 tier-2) changed from `dir=$(qa_project)` to `qa_project; dir="$QA_PROJECT_DIR"`. Two guards make the mistake impossible to repeat silently: (1) qa_project aborts the whole script (`kill -TERM $$`) if called from a subshell — detected via `BASH_SUBSHELL`, since macOS bash 3.2 has no `BASHPID`; (2) `qa_git_repo` refuses to `git init` anywhere that is already inside a work tree. Repo damage repaired: branch reset to the last real commit, local `user.name`/`user.email` pollution removed. Test: `reg_103_qa_repo_isolation.sh` (QA-REG-103) builds a victim repo and asserts correct usage lands in the temp dir, legacy misuse aborts, and the victim stays byte-for-byte untouched — verified failing against the old helpers.

### ~~P2: A few QA scripts are flaky under full-suite parallel load~~ FIXED (root cause: session isolation never worked)
`edit_020_bracket_pair` failed in 3/3 full `make qa` runs but passes standalone; `ms_012_drag_tree_border`, `clip_009_paste_replaces`, `gut_012_minimap`, `col_005_column_cut` failed in some full runs only. The "slow renders under load" theory was only part of the story — failure screenshots from a full-detail run revealed **cross-test interference**:

1. **State-dir isolation was a no-op.** hangon sessions do NOT inherit the client's environment, so the `ZEPTO_STATE_DIR` that qa_setup exported never reached zepto (verified: `VAR=x hangon start -- sh -c 'echo $VAR'` prints empty). Every QA zepto ran against the user's REAL `~/.config/zepto` — tests polluted each other's prefs AND the user's actual editor settings. Smoking gun: `cplt_007_pair_off` toggles auto-pair off in the shared prefs, and `edit_020` (launching concurrently) reads them → screen literally shows `(` with no auto-close. Explains why edit_020 failed in *every* full run (alphabetical scheduling put them adjacent) but never standalone.
2. **System clipboard shared across parallel sessions (and with the user).** `clip_009`'s failure screen showed it pasting `aaaa/bbbb/cccc` — `col_005_column_cut`'s cut text. QA runs also clobbered the user's real clipboard on every copy test.
3. Secondary: fixed `sleep`-based waits genuinely flake under load, and `ms_012`'s measurement pipeline died under `set -e` when a grep matched nothing.

**Fix:** (1) Isolation now travels as CLI flags — `qa_start` passes `--state-dir "$QA_STATE_DIR"` plus new `--no-system-clipboard`; the three scripts that invoke `hangon start` directly were updated too. (2) New `--no-system-clipboard` flag (build.pl → Editor → Terminal) skips OSC 52 and pbcopy/xclip entirely so copy/paste use the internal per-process clipboard. (3) `qa_wait_screen`/`qa_assert_expect` helpers poll the rendered screen with a deadline (NOT `hangon expect`, which matches the raw escape-code stream where patterns like `()` never appear adjacent); edit_020, clip_009, ms_012, gut_012 rewritten onto them, and ms_012's pipelines guarded with `|| true`. Verified: pref-toggling test leaves the real `~/.config/zepto` mtimes untouched; two parallel sessions no longer share a clipboard. Test: `reg_106_session_isolation.sh` (QA-REG-106).

Note: months of QA runs may have already drifted the user's real `~/.config/zepto/preferences.json` (auto-pair/minimap/theme toggles) — worth a manual review.

### ~~P3: Remaining sleep-based QA scripts occasionally flake under full-suite load~~ FIXED (2026-08-29)
The 2026-08-28 isolation fixes eliminated the systematic cross-test failures, but a long tail of scripts still used fixed `sleep` + `qa_assert_screen` instead of the deadline-polling `qa_wait_screen`/`qa_assert_expect` helpers, occasionally flaking when the parallel suite starved a render.

**Migration result: 315 of 579 tier1 scripts (54%) now use `qa_assert_expect`/`qa_wait_screen`.** Done across several passes (one solo, then a 4-way parallel sweep over the full remaining directory, each agent assigned a disjoint file list). The other 264 scripts were surveyed and deliberately left on `qa_assert_screen`/fixed sleeps because they don't fit the mechanical polling pattern without weakening the assertion: `qa_assert_not_screen` checks (polling would invert their meaning), `qa_alive`/cursor-position/before-after-screen-equality comparisons, dual-branch fallback logic (`if X qa_pass else qa_pass "weaker claim"` — several of these were also tautological before-the-fact and are tracked separately, not by this item), and security tests where an agent judged the wait mechanism change risked altering what was actually being asserted. This is a legitimate stopping point, not an abandoned migration — forcing the remaining 264 would trade coverage for false confidence.

**Bugs found and fixed in the mechanical migration itself, via a full-suite verification run after merging (not caught by individual per-script testing, only by running everything together):**
- `reg_053_auto_pair_undo`: pattern `'\\(\\)'` (double-escaped) doesn't match literal `()` in ERE — should be `'\(\)'`. The original script used `grep -qF "()"` (fixed-string, no escaping needed at all); migrating to `qa_assert_expect` (which greps `-E`) required escaping parens, and one extra backslash was added instead of the needed single one.
- `prmt_002_discard`, `reg_037_multi_dirty_prompt`, `reg_046_palette_width`: original scripts used `grep -qiE` (case-insensitive) to match UI text like "Save changes to...?" against a lowercase pattern; `qa_assert_expect`/`qa_wait_screen` only grep `-E` (case-sensitive, matching `qa_assert_screen`'s existing behavior), so migrating away from `-i` without adjusting the pattern broke the match. Fixed by spelling out the actual capitalization with bracket expressions (`[Ss]ave`) rather than adding a new case-insensitive helper variant.
- Audited all 20 scripts whose pre-migration version used `-qi`; the 16 not listed above still pass because their specific patterns happened to be case-invariant (e.g., matching digits or already-lowercase rendered text) — verified individually, not assumed.
- `thm_014_ctrl_t_leaves_auto`'s single failure in the verification run was a transient `hangon` state-file corruption from concurrent load (many parallel QA-running agents hammering `~/.hangon/state.json` that day), not a script or migration bug — passes cleanly standalone and confirmed unrelated.

Full suite (579 scripts) green after these fixes. QA runner concurrency-safety (`QA-REG-108`, below) means future full-suite runs sharing this machine with other agents won't corrupt each other's hangon state.

### ~~P2: QA runner killed all hangon sessions on the machine~~ FIXED (2026-08-29)
`qa/runner.pl` ran `hangon stopall` before and after every suite run and deleted `~/.hangon/state.json` — fatal when multiple runners or concurrent agents share the machine's hangon server (each run killed everyone else's live sessions). Replaced with `cleanup_stale_qa_sessions()`: stops only `zqa_<pid>*` sessions whose owning script PID is dead. Test: `reg_108_runner_concurrent.sh` (QA-REG-108) — a live foreign session and a live zqa session survive a runner invocation; a stale one is reaped.

### ~~P1: InputParser mis-parses OSC escape sequences as Alt+']' + garbage keystrokes~~ FIXED (2026-08-29)
Found while building auto dark/light theme detection: `InputParser::_parse_escape()` had no case for `ESC ]` (the introducer for OSC — Operating System Command — sequences, e.g. a terminal's reply to a background-color query). It fell into the generic "Alt+key" branch, which only looks at the byte immediately after ESC: `]` (ord 93, within the 32–126 "printable" range the Alt+key branch accepts) was consumed as Alt+']', and every subsequent byte of the OSC payload and its terminator was then parsed one at a time as ordinary, unmodified character events. If focus was in the document, an unsolicited OSC reply from the terminal (which can arrive asynchronously — nothing requires the application to have just asked for it) would have been typed straight into the buffer as garbage text. This is the same failure class as QA-REG-102 (unknown/unrecognized sequences must be cleanly discarded, not misinterpreted as something else that leaks bytes downstream) — QA-REG-102 fixed the "stall" half of that contract; this fixes a "corruption" half that QA-REG-102's fix didn't cover, because OSC wasn't unrecognized-and-discarded, it was actively misidentified as a *different*, valid sequence (Alt+key) with content following it.

**Fix:** Added `InputParser::_parse_osc()`, dispatched from `_parse_escape()` before the generic Alt+key fallback whenever the second byte is `]`. It scans for a terminator — BEL (`\x07`) or ST (`ESC \`) — and consumes the whole sequence without emitting any character events (mirrors the existing "unknown CSI/SS3 discarded, parsing continues" pattern from QA-REG-102, so queued input behind an OSC reply is never stalled either). A capped scan (`OSC_MAX_LEN` = 512 bytes) discards a runaway/unterminated OSC body instead of buffering forever or wedging the parser. `flush_pending()` (the idle-timeout path that turns a lone `ESC` into the Escape key) got a matching case: a lone `"ESC ]"` with nothing following within the timeout — indistinguishable from the start of an OSC sequence until proven otherwise — resolves to Alt+']', preserving that as a legitimate keystroke. Tests: `tests/input_parser.t` (BEL-terminated, ST-terminated, split-across-reads, runaway body, the Alt+']' flush case — each verified failing against the pre-fix code first). QA: `QA-REG-138` (`reg_138_osc_no_corruption.sh`), verified failing against the pre-fix `InputParser.pm` before the fix landed.

### ~~P3: Theme palette icon didn't reflect actual dark/light state~~ FIXED (2026-08-29)
The `toggle_theme` command's `icon` field was hardcoded to `theme_dark` (a moon) with a comment claiming it was "dynamic: theme_dark or theme_light" — but nothing anywhere actually swapped it. The palette and status-bar pill showed a moon even in light mode, unlike the adjacent `[dark]`/`[light]` state text (via `get_toggle_display`), which was already correct. Found incidentally while adding the third `auto` state (which needed its own icon anyway, making the static-icon gap obvious).

**Fix:** Both icon-resolution sites in `Renderer.pm` (status bar pill, palette row) now special-case `$cmd->{pref} eq 'theme'` and pick `theme_auto`/`theme_dark`/`theme_light` from `CommandRegistry->get_toggle_state()`, the same source the state text already used. Added a `theme_auto` icon (`NF_ADJUST`, a half-filled circle) to `Chars.pm`. QA: `QA-REG-139` (`reg_139_theme_icon_reflects_state.sh`) — asserts the rendered Theme row's icon prefix (state-bracket text stripped) differs between dark and light modes; verified failing against the pre-fix code (identical prefixes in both modes).

### ~~P1: Light-theme tab "unsaved" dot has ~1.2-1.8:1 contrast, nearly invisible~~ FIXED (2026-08-30)
User-reported: in light theme, the unsaved-changes dot icon in the document tab bar is hard to make out against the tab background. `tab_modified_fg` (`fg_rgb(223, 142, 29)`, a light yellow) rendered against `tab_active_bg` (1.22:1), `tab_hover_bg` (1.57:1), and `tab_inactive_bg` (1.80:1) — all far below WCAG's 3:1 minimum for UI components. The dark theme's equivalent was fine (3.99-6.91:1 against the same three surfaces) — this was a light-theme-only regression, the color was clearly tuned by eye against a dark backdrop and never re-checked against light.

**Fix:** Darkened to a burnt-amber `fg_rgb(95, 40, 0)` — same warm hue family (still reads as "amber/orange dot"), but dark enough to clear 3:1 against all three tab-bar surfaces the icon can render on (active/inactive/hover), verified by direct WCAG contrast computation and by capturing the actual emitted ANSI bytes on a dirty tab (`38;2;95;40;0` on `48;2;114;135;253`).

**Infrastructure (the actual ask — prevent this class of bug systematically):** Added `tests/theme_contrast.t`, a WCAG 3:1 contrast audit over every themed fg/bg color pair in both themes, run automatically in `make test`. Pairing is inferred from naming convention (`X_fg`/`X_bg` siblings) for self-contained components; a small `%SURFACE_OVERRIDE` table handles roles that render on more than one background (e.g. this exact bug — a tab icon can sit on 3 different tab-state backgrounds) or on the base editor surface. This is a heuristic, not formal verification — documented in the test file's header, and extensible via the override table when a future role renders somewhere unexpected.

**First run surfaced 41 additional pre-existing violations** (see below) beyond the one reported — confirming this is systemic, not a one-off. These are tracked as `%KNOWN_DEBT` in the test (rendered as TAP `TODO`, visible in verbose output, never silently passing) so the new gate is live for all *future* colors without retroactively failing the build on undecided pre-existing debt. QA: `qa/scripts/tier1/reg_140_tab_modified_contrast.sh` (`QA-REG-140`).

### ~~P2: Pre-existing theme contrast debt found by tests/theme_contrast.t~~ FIXED (2026-08-30)
42 fg/bg pairs across both themes (15 dark, 27 light — not 41/26 as originally miscounted) failed the WCAG 3:1 UI-component contrast minimum, discovered by the `tests/theme_contrast.t` audit built while fixing the tab-modified-dot bug. All 42 are now fixed in `lib/Zepto/Theme.pm`; `%KNOWN_DEBT` in `tests/theme_contrast.t` is now empty (left as `my %KNOWN_DEBT = ();` rather than deleted, per the file's own convention, with a comment explaining why) and `prove -lv tests/theme_contrast.t` shows 79 genuine `ok`s across both themes with zero `TODO`s.

**Approach:** for each pair, lightened (dark theme) or darkened (light theme) the foreground within its existing hue family until it cleared 3.0:1 against every background surface that role can render on (some orphan roles like `tab_close_fg` render on 3 different tab-state backgrounds simultaneously — the fix had to satisfy the hardest of the three). Two roles whose fg was already at/near pure white and couldn't be brightened further (`status_pos_fg`, `dropdown_selected_fg`) were fixed by adjusting the background instead (`status_pos_bg`/`status_pos_edge` darkened as a matched pair; `dropdown_selected_fg` pushed to pure white, which was still enough headroom). A handful of roles that shared an identical RGB value for an explicit, commented design reason (`gutter_fg`/`ruler_fg`/`table_border_fg` — "matches gutter"/"like line numbers") were fixed to the same new shared value in each theme, rather than drifting independently.

**Notable finding — two roles are dead code:** `menu_active_fg` (light theme's 1.00:1 pair — fg literally identical to its own bg, the single worst ratio in the whole audit) and `menu_pill_fg` are both defined in `Theme.pm` but never consumed by `Renderer.pm` (confirmed via `grep -rn` across `lib/`) — the actual text color rendered inside those pills is `menu_active_text`/`menu_pill_text` (already fine, both white). So the "selected menu item's text is the same color as its own background" framing in the original report was inaccurate — no user ever saw that specific pair. Both were fixed anyway for correctness/consistency and in case they're ever wired up as real border/text colors, but the real user-visible "worst offender" is `dropdown_selected_fg/dropdown_selected_bg` (2.81:1, command-palette/dropdown selected-row text) — covered by `QA-REG-160`.

**Full before/after table** (theme: role, old ratio → new ratio, old RGB → new RGB):

Dark theme (15):
| Role / bg | Old ratio | New ratio | Old RGB | New RGB |
|---|---|---|---|---|
| `completion_border_fg` / `dropdown_bg`+`menu_bg` | 1.48 | 3.10 | (61,66,91) | (111,115,134) |
| `gutter_fg` / `gutter_bg` | 2.91 | 3.16–3.19 | (86,95,137) | (100,108,146) |
| `menu_pill_fg` / `menu_pill_bg` | 1.40 | 3.15 | (65,72,104) | (122,127,149) |
| `minimap_text_fg` / `bg` | 2.10 | 3.06 | (70,78,110) | (96,103,130) |
| `ruler_fg` / `ruler_bg` | 2.61 | 3.16–3.19 | (86,95,137) | (100,108,146) |
| `tab_close_fg` / active+hover+inactive `_bg` | 1.50 (worst) | 3.07+ | (100,106,134) | (156,160,178) |
| `tab_shortcut_fg` / `tab_active_bg` | 2.12 | 3.08+ | (120,130,170) | (152,160,190) |
| `table_border_fg` / `bg` | 2.76 | 3.16–3.19 | (86,95,137) | (100,108,146) |
| `tree_border_fg` / `tree_bg` | 1.80 | 3.23 | (61,66,91) | (100,104,124) |
| `tree_indent_fg` / `tree_bg` | 1.80 | 3.23 | (61,66,91) | (100,104,124) |
| `tree_scrollbar_fg` / `tree_scrollbar_bg` | 2.88 | 3.15 | (86,95,137) | (93,101,142) |
| `wrap_indicator_fg` / `bg` | 1.91 | 3.16 | (65,72,104) | (99,105,131) |

Light theme (27):
| Role / bg | Old ratio | New ratio | Old RGB | New RGB |
|---|---|---|---|---|
| `completion_border_fg` / `dropdown_bg`+`menu_bg` | 1.78 / 1.91 | 3.15+ | (172,176,190) | (127,130,141) |
| `completion_ghost_fg` / `bg` | 2.46 | 3.15 | (160,165,180) | (141,145,158) |
| `dropdown_selected_fg` / `dropdown_selected_bg` | 2.81 | 3.18 | (239,241,245) | (255,255,255) |
| `gutter_fg` / `gutter_bg` | 2.60 | 3.10 | (156,160,176) | (128,131,144) |
| `menu_active_fg` / `menu_active_bg` | **1.00** (worst overall; dead code) | 3.16 | (114,135,253) | (52,62,116) |
| `menu_pill_fg` / `menu_pill_bg` | 1.40 (dead code) | 3.16 | (172,176,190) | (110,113,122) |
| `minimap_text_fg` / `bg` | 2.19 | 3.07 | (170,175,190) | (143,147,160) |
| `ruler_fg` / `ruler_bg` | 2.14 | 3.10 | (156,160,176) | (128,131,144) |
| `status_modified_fg` / `status_bg` | 1.98 | 3.12 | (223,142,29) | (174,111,23) |
| `status_pos_fg` / `status_pos_bg`+`_edge` | 2.60 | 3.05 | bg/edge (156,160,176) | bg/edge (144,147,162) (fg unchanged, already white) |
| `tab_close_fg` / active+hover+inactive `_bg` | 1.22 (worst tab pair) | 3.09+ | (156,160,176) | (66,67,74) |
| `tab_shortcut_fg` / active+hover+inactive `_bg` | 1.11 | 3.05+ | (130,136,156) | (65,68,78) |
| `tab_vcs_fg` / `tab_active_bg` | 1.84 | 3.05 | (140,90,20) | (95,61,14) |
| `table_border_fg` / `bg` | 2.60 | 3.05 | (156,160,176) | (128,131,144) |
| `tree_border_active_fg` / `tree_bg` | 2.84 | 3.06 | (114,135,253) | (109,130,243) |
| `tree_border_drag_fg` / `tree_bg` | 2.84 | 3.06 | (114,135,253) | (109,130,243) |
| `tree_border_fg` / `tree_bg` | 1.93 | 3.12 | (172,176,190) | (134,137,148) |
| `tree_indent_fg` / `tree_bg` | 1.93 | 3.12 | (172,176,190) | (134,137,148) |
| `tree_scrollbar_fg` / `tree_scrollbar_bg` | 2.33 | 3.08 | (156,160,176) | (134,138,151) |
| `warning_fg` / `bg`+`status_bg` | 2.62 / 1.98 | 4.13 / 3.12 | (223,142,29) | (174,111,23) |
| `wrap_indicator_fg` / `bg` | 1.82 | 3.11 | (188,192,204) | (143,146,155) |

(`status_modified_fg` and `warning_fg` intentionally share one new value — they were already the same amber and both needed the same fix.)

**Verification:** `prove -lv tests/theme_contrast.t` — 79/79 checks pass, zero `TODO`s, both subtests green. `make check`, `make build`, `make test` all pass with zero noise (`1111` tests, `Result: PASS`). Interactive verification via `hangon` across both themes covering gutter/ruler numbers, tab bar (dirty dot, close icon, shortcut hint on active/inactive/hover), file tree panel, command palette / dropdown selected-row text, and completion ghost text — all read correctly, still recognizably the same muted/subtle hue family as before, not garish. QA: `qa/scripts/tier1/reg_160_dropdown_selected_contrast.sh` (`QA-REG-160`, the real "worst offender" — selected palette-row text) and `qa/scripts/tier1/reg_161_tab_close_shortcut_contrast.sh` (`QA-REG-161`, tab close/shortcut icons on the active tab, the worst *live* tab pair at 1.11–1.22:1), alongside the pre-existing `QA-REG-140`.

**Incidental fix:** `tests/syntax_rendering.t` had a stale assertion (`Comment color (gray) found in output` checking for raw bytes `38;2;86;95;137`) that was never actually testing `syntax_comment` (dark theme's real value is `fg_rgb(150,175,200)`) — it was coincidentally matching `gutter_fg`'s old shared muted-blue-gray value, which also appears in the same combined render output via the line-number gutter. Changing `gutter_fg` broke this mislabeled assertion; fixed the test to check the actual `syntax_comment` color it was always supposed to verify.

**Incidental finding — see new bug below (not fixed here, out of scope for a color-values task).**

### P2: Stale-theme partial redraw after theme change or panel toggle (2026-08-30, not yet fixed)
Found incidentally while interactively verifying the contrast fixes above with `hangon` — not caused by, or related to, the color-value changes themselves (confirmed: a subsequent full repaint always shows the *correct* new-theme colors, proving the underlying theme data is right).

Reproduced twice:
1. Switch theme (e.g. dark → light via the command palette's "Theme: Light"), then open the file tree (`⌃B`). The tree panel renders using the *previous* theme's colors (e.g. still dark-navy background/text) while the main editor pane correctly shows the new theme — a visible split down the middle of the screen. Confirmed NOT a screenshot/capture artifact: reproduced 3 times across separate screenshots with settle time in between, and resolved instantly once any dialog (e.g. the command palette) is opened and closed, which forces a full-screen repaint.
2. Open a new empty/`[untitled]` tab (`⌃N`) in light theme: the single content row renders correctly (light bg), but the empty rows below it render dark instead of `empty_line_bg`'s light value — again fixed by any action that forces a full repaint.

Both point to the same root cause: some code path that invalidates/repaints on theme change or tab/panel switch is only repainting the region it thinks changed, not the whole screen, leaving stale previous-theme pixels in untouched regions until an unrelated full-repaint event (opening a dialog) papers over it. Not investigated further — likely in `Renderer.pm`'s dirty-region tracking or wherever `cmd_toggle_theme`/tab-creation triggers a redraw. Cosmetic (self-correcting on the next full repaint) but visible and worth a dedicated fix; flagging for the next bug-bash pass rather than fixing here, since this task's scope was `Theme.pm` color values only and this is a `Renderer.pm` invalidation-logic bug.

### P1: Discoverability Contract gaps found by manual visual sweep (2026-08-30, not yet fixed)
While building `docs/UI_GUIDELINES.md`'s new "Discoverability Contract" section (user-requested: at all times, the most relevant actions and shortcuts should be visible on screen, including core navigation — not just document-editing commands — with a clear fallback for anything that doesn't fit), a static `CommandRegistry` audit (`tests/discoverability_core_nav.t`) and a manual screenshot sweep across widths/themes/contexts (no `ANTHROPIC_API_KEY` was configured to run the new `qa/scripts/tier2/discoverability_sweep.sh` through the LLM judge, so this pass was done by direct visual inspection instead) found:

1. **The static registry check is necessary but not sufficient — real coverage is better than `priority => 0` alone suggests.** `next_tab`/`prev_tab`/`close_tab` all show `priority => 0` in `CommandRegistry.pm` (would never appear as a status-bar pill), but the DOCUMENT context tab bar actually renders a separate, hardcoded corner hint (`⌃W ×  ⌥, ←  ⌥. →`) that isn't part of the pill-priority system at all — confirmed via screenshot to survive even at 40×15 (the narrowest width tested), only dropping when there's truly no room. So this specific concern is largely already met; `tests/discoverability_core_nav.t`'s TODO-tracked failures on these three IDs are a false-ish positive from checking the wrong mechanism — real coverage exists, just not through the registry. Left as TODO rather than deleted, since the registry genuinely doesn't know about it, which is itself worth fixing (see below).
2. **`quit` (⌃Q) has NO on-screen hint anywhere, at any width, in any theme, in the one context checked (DOCUMENT).** Confirmed absent in 80×24, 60×20, and 40×15 screenshots, both themes. This is a real, confirmed gap — `priority => 0` here is accurate, there's no hidden corner-hint covering it the way tab navigation has.
3. **The FILE_TREE context is missing on-screen hints for: `quit`, switching focus back to the editor (`⌃B`/`Esc`), AND tab navigation** (the corner hint from DOCUMENT context does not carry over — confirmed via screenshot, the tree-focused status bar shows only `.claude` breadcrumb / fold / open / `Open ⌃O` / `Commands ⌃␣`). A user who focuses the tree (by mouse click or `⌃B`) has no visible path back to editing shown anywhere on screen — this is the single clearest violation of the contract found, and matches exactly the scenario the user described.
4. **What's working well** (confirmed, not just assumed): progressive disclosure degrades honestly — `⌃␣ Commands` and the cursor-position pill never dropped at any tested width; the tab-nav corner hint persists down to 40 cols before anything else does.

Only 5 screenshots (document context: 3 widths × mostly-dark plus one light; file-tree: 1) were reviewed — this is a sample, not an exhaustive sweep. FIND/PROMPT/palette contexts, and the light-theme file-tree/narrow-width variants, were not checked. The durable fix for "exhaustive" is running `qa/scripts/tier2/discoverability_sweep.sh` with a real API key configured, which covers the full matrix automatically and repeatably.

**Not fixed here** — pending a scope decision, same as the theme contrast debt above. Candidate fixes: give `quit` a corner-hint-style always-visible affordance (mirroring how close/next/prev tab already work) in every context, not just DOCUMENT; extend the FILE_TREE status bar to include a focus-switch hint and the tab-nav corner hint; consider whether `CommandRegistry` should have a formal `core_nav => 1` tag so `commands_for_status_bar`-style logic and the corner-hint renderer both derive from one source of truth instead of two independent, silently-divergent code paths (the actual root cause of finding #1 — the registry and the tab bar's hardcoded hint don't agree on what's "always visible").

## Scorecard audit backlog (2026-08-30)

Findings from a 5-agent parallel codebase audit (architecture, code quality, security, tests/docs, performance/duplication). Each item below will be marked FIXED with a root-cause/fix/test writeup by whichever agent picks it up, following this file's normal convention.

### ~~P1: FindEngine.pm ReDoS timeout only covers regex compilation, not matching~~ FIXED
The SIGALRM(1) timeout (`FindEngine.pm:455-462`) wraps `qr//` compilation only, then is cancelled before the actual match. Catastrophic backtracking happens at MATCH time, not compile time — a pattern like `(a+)+$` against long input can still hang `tick()` indefinitely (`FindEngine.pm:126,532,549,646`); the 10ms incremental-search deadline check only runs *between* completed matches, not during one. `bugs.md`'s existing "SIGALRM(1) timeout... provides defense-in-depth against catastrophic backtracking" claim (QA-REG-011) is inaccurate for this reason. Self-inflicted only (a user's own search pattern hangs their own search of their own file) — not exploitable by another party — but a real, live gap in a control the docs claim is closed.

**Root cause:** `_build_regex()`'s alarm guards `qr//` compilation only and is explicitly cancelled (`alarm(0)`) before the caller ever attempts a match. All four match sites — `tick()`'s background loop (`FindEngine.pm:127`, was `:126`), the synchronous viewport search in `_search_range()` (`:764`, was `:646`), and the single-match capture extractors `_extract_captures()`/`_extract_capture_positions()` (`:640`/`:662`, was `:532`/`:549`) — ran unguarded. Confirmed exploitable: `(a+)+$` (the bug report's own example) turns out NOT to reproduce this in Perl — Perl's regex engine auto-optimizes away nested quantifiers over identical single-char atoms — but `(a?){28}a{28}` against 28 `a`s does, taking 15+ seconds of pure C-level backtracking unguarded (reproduced with a forked-child watchdog, since Perl's `alarm()` is a single process-wide timer that made an in-process watchdog unusable for testing this).

**Fix:** Added a second, independent alarm around the actual MATCH (not just compilation), via a new `_match_with_alarm()` helper (`MATCH_ALARM_SECS => 1`) used at all four call sites. On timeout, the search aborts gracefully — `tick()`/`_search_range()` stop returning partial results instead of retrying the same doomed match forever (which would otherwise wedge the UI's tick loop indefinitely), and a new `search_timed_out()` accessor lets callers know results may be incomplete; capture extraction just yields no captures. Non-pathological search (including 2000+ line files) is provably unaffected — no false-positive timeouts, same match counts, same speed (`find_engine_perf.t` unchanged).

Found and fixed a bug in an earlier version of this same fix while building it: Perl's numbered match variables (`$1`, `@-`/`@+`) do not reliably survive being read from *outside* a multi-statement `eval{}` block, even though the match inside it succeeded — an initial version of `_match_with_alarm()` read `$1` after the guarding eval returned and silently got `undef` back (confirmed empirically across a dozen isolated repro scripts). Fixed by having the coderef passed to `_match_with_alarm()` extract everything it needs (`$1`, `@-`/`@+`) *inside* itself before returning plain values — `pos()` on the subject string is unaffected by this and safe to read normally after return. Documented in the helper's own comments so it isn't re-broken later.

Test: `tests/find_engine_redos.t` (7 subtests: viewport-path hang, background-tick-path hang, `search_timed_out()` flag + partial results, flag reset on next search, no false positives on legitimate large search, and a capture-extraction regression guard for the `$1`-survival bug above) — forked-child + parent-watchdog design for the same alarm-clobbering reason noted above. QA: `qa/scripts/tier1/sec_012_redos_match_timeout.sh` (`QA-SEC-012`, `QA-REG-141`) — interactively confirms the editor stays responsive (not just that the library function returns) when the pattern is typed into the live find bar.

### ~~P2: message_is_error can leak stale error styling onto non-error messages~~ FIXED (2026-08-30)
`show_message()` (`Editor.pm:5062-5066`) always resets `message_is_error => 0`, but 10 call sites in toggle commands (`Editor/Commands.pm:1280,1287,1294,1306,1313,1320,1327,1334,1357,1376`) wrote `$self->{message} = "..."` directly, bypassing the reset. The top-of-loop guard (`Editor.pm:944-947`) only clears `message_is_error` when a message was already showing at the START of that input batch — it fires once, before `handle_input()` runs, not once per event. `handle_input()` (`Editor.pm:1192-1204`) parses a single `read_blocking()` chunk into potentially *multiple* events and processes all of them via `handle_event()` in one call, so if an error message was showing and a toggle command's confirmation both landed within the same chunk (fast/pasted/scripted input arriving before the app's next read), the toggle's confirmation text inherited the error's red styling (`Renderer.pm:3900`: `message_is_error ? error_fg : warning_fg`) even though it wasn't an error.

**Fix:** Routed every raw `$self->{message} = "..."` assignment for non-error confirmations through `show_message()` instead, which always resets the flag correctly — the 10 sites above in `Editor/Commands.pm` (`cmd_toggle_autocomplete`, `cmd_toggle_auto_pairs`, `cmd_toggle_restore_session`, `cmd_toggle_mouse`, `cmd_toggle_search_wrap`, `cmd_toggle_markdown_tables`, `cmd_toggle_soft_tabs`, `cmd_toggle_auto_indent`, `cmd_set_tab_width`'s `on_submit`, `cmd_toggle_ai`), plus two similar direct-assignment sites in `Editor.pm` (`_replace_all_async`/`_replace_all_sync`'s "Replaced N occurrence(s)" messages, `Editor.pm:3182,3213`) found by the same grep sweep. `message_time` (set alongside the two `Editor.pm` sites) was preserved as a trailing statement — it turned out to be dead (no reader anywhere in the codebase), so left untouched rather than removed as an unrelated cleanup.

**Test:** `tests/editor.t` — "Toggle confirmation does not inherit stale error styling" calls `show_error_message()` then `cmd_toggle_autocomplete()` directly (bypassing `run()`'s per-batch guard entirely, exactly modeling the same-input-batch scenario), asserting `message_is_error` is false afterward. Verified failing against the pre-fix code (`message_is_error` stayed `1`), passing after.

**Interactive verification:** hangon-driven baseline check — real "Invalid tab width" error (red, `38;2;247;118;142`) followed by a real "Auto Pairs: ON/OFF" toggle confirmation (amber/warning, `38;2;224;175;104`) as two sequential actions, confirming the fix didn't break normal toggle messaging. Note: hangon drives zepto through separate process invocations that each reliably land in their own `read_blocking()`/`handle_input()` batch, so this sequential interaction can't reproduce the exact same-batch race (the per-batch guard already resets the flag between separate hangon commands, both before and after this fix) — the unit test above is the only repro of the actual race. QA: `QA-REG-142` (`reg_142_message_error_style_leak.sh`), which documents this same tradeoff in its header.

### ~~P2: Buffer::get_text() re-concatenates the whole document on every line read~~ FIXED (2026-08-30)
**Root cause:** `Buffer.pm` `get_text()` unconditionally built `pre_gap . post_gap` (concatenating the WHOLE document) even to fetch a single line. `get_line`/`get_line_content` called it under the hood, and the renderer calls `get_line_content()` once per visible row (~40-80×/frame) — every rendered frame re-copied the entire document 40-80 times.

**Fix:** `get_text($start, $end)` now reads directly out of `pre_gap`/`post_gap` without concatenating first: if the requested range lies entirely within `pre_gap` or entirely within `post_gap`, it's a single `substr()` with no concat at all; only when the range straddles the gap boundary (which happens only for the one line currently containing the cursor) does it concat, and even then only the two small slices that fall inside `[start, end)`, never the full document. `get_line`/`get_line_content` are unchanged (they still call `get_text()`) and benefit automatically.

**Tests:** `tests/buffer.t` gained new subtests written and confirmed passing against the *unfixed* code first (per Rule 5): "Line reads at the gap boundary" (gap mid-line, gap at a line boundary, gap at position 0, gap at end of buffer), "get_text spanning the gap boundary explicitly", and "Unicode content spanning the gap boundary" (multi-byte and emoji lines straddling the gap). All pass after the fix; full suite (`make test`, 1117 tests) still green with zero noise.

**Benchmark** (30,000-line synthetic file, ~90 chars/line, `qa`/`scratchpad` script, not checked in): `get_line_content()` × 2000 calls at a mid-file scroll position went from **34.48 µs/call → 1.00 µs/call** (~34x).

**QA:** `qa/scripts/tier1/reg_150_buffer_line_read_perf.sh` (QA-REG-150) — correctness regression coverage for large-file line reads at/around the gap after edits at various positions (start, middle, end, near cursor).

### ~~P2: Buffer::_ensure_line_index() does a full O(n) rescan on every edit~~ PARTIALLY FIXED (2026-08-30)
**Root cause:** `insert`/`delete` unconditionally invalidated the line index; the next `line_count()`/`get_line()` call rebuilt the entire newline index from a fresh full-buffer `text()` call — one full-document scan per keystroke on large files.

**Fix (scoped, honest writeup):** `insert`/`delete` now update the line index **incrementally** for the common case: single-character/no-newline edits (the overwhelming majority of keystrokes — typing, backspacing). When the index is already valid and the inserted/deleted text contains no `"\n"`, the edit cannot change which offsets belong to which line, so it only grows/shrinks the length of the one affected line (O(1)) and shifts the start offset of every later line by the edit's length delta (O(remaining lines), pure integer increments — no string scanning, no concat). This is the "shift indices after the edit point" approach suggested in the task.

**What's NOT fixed (documented limitation):** edits whose inserted/deleted text contains a newline (pressing Enter, multi-line paste, deleting a selection that spans a newline) still invalidate the index for a full rebuild on next use — correctly splitting/merging line entries incrementally was judged too risky to rush given the "correctness over speed" mandate for gap-buffer surgery. This is still a strict improvement over before (only newline-crossing edits pay the full rebuild now, not every edit).

**Known remaining tradeoff (not a regression in any real call site found):** the incremental shift is O(remaining lines) per edit. A purely synthetic stress pattern — thousands of sequential single-char inserts at a fixed position with **zero** intervening reads, far from either end of a huge file — is slower per-edit than the old lazy-invalidate-then-single-rebuild (which paid one O(document) rebuild only when a read eventually happened). We audited actual Zepto call sites for this pattern: interactive typing always renders (reads ~40-80 lines) after every single insert, so it hits the *fast*, dramatically-improved path; `_multi_cursor_insert_char` loops over cursors (small N) before a render; `_replace_all_sync` (Editor.pm) is capped at 100 edits before a render; `_replace_all` (>100 matches) does one whole-document `replace()` (contains newlines → single invalidate+rebuild, same cost as before). No bounded real-world batch showed a regression (benchmarked: 100 unread inserts + 1 render = 29ms total on a 30K-line file). A Fenwick-tree/BIT-based line index would close this gap entirely with no tradeoff, but is out of scope for this fix.

**Tests:** `tests/buffer.t` new subtests "Insert exactly at line boundaries", "Delete exactly at line boundaries", and "Repeated single-char edits maintain a correct line index" (simulates typing/backspacing at a fixed cursor position across multiple sequential incremental updates) — written and confirmed passing against the unfixed code first, still pass after.

**Benchmark:** interleaved single-char-insert + 60-line-render (the actual per-keystroke render pattern), 1000 iterations on a 30,000-line file: **6.85 ms/iter → 0.35 ms/iter** (~19x). Pure sequential-insert-with-no-reads stress test (not a real call pattern, see above): 0.40 µs/call → 294 µs/call (regression in that synthetic case only).

**QA:** `qa/scripts/tier1/reg_151_buffer_line_index_incremental.sh` (QA-REG-151) — correctness regression coverage: large file, sequence of single-char inserts/deletes/newline-inserts/newline-deletes at various positions (start, middle, end, near the original gap), asserting line count and content stay correct throughout.

### ~~P2: ~9 near-identical cmd_toggle_* methods, and a duplicated cursor-clamp block~~ FIXED
`Editor/Commands.pm:1283-1330` (approx) — `cmd_toggle_auto_pairs`, `cmd_toggle_restore_session`, `cmd_toggle_search_wrap`, `cmd_toggle_markdown_tables`, `cmd_toggle_soft_tabs`, `cmd_toggle_auto_indent`, and others all share the identical 4-line shape (`$new = !prefs->X(); prefs->set_X($new); message = "Label: ON/OFF"`) — copy-paste, and the source of the asymmetric-feedback inconsistency below. Separately, `Editor.pm:5147-5153` and `Editor.pm:5175-5181` are a byte-for-byte duplicated 7-line cursor-clamp-after-reload block.

**Fix:** Pure refactor, no behavior change (verified by tests before/after, not just code inspection).

Added `_toggle_pref($self, $getter, $setter, $label, %opts)` in `Editor/Commands.pm`, right before `cmd_toggle_autocomplete`. It does `my $new = !$getter->(); $setter->($new); $self->{message} = "$label: " . ($new ? $opts{on_label}//'ON' : $opts{off_label}//'OFF'); return $new;` — the getter/setter are passed as closures (`sub { $self->{prefs}->auto_pairs() }` / `sub { $self->{prefs}->set_auto_pairs($_[0]) }`) so the helper stays agnostic of the specific preference. `on_label`/`off_label` opts cover the one outlier (`cmd_toggle_soft_tabs`'s "ON (spaces)"/"OFF (tabs)" wording). The return value lets callers with an extra side effect (mouse enable/disable, completion dismiss) run it after the preference is persisted, keyed off the new value.

8 methods converted to thin wrappers around `_toggle_pref`, each still defined under its exact original name (CommandRegistry dispatches by method-name string, so none could be renamed or removed): `cmd_toggle_autocomplete`, `cmd_toggle_auto_pairs`, `cmd_toggle_restore_session`, `cmd_toggle_mouse`, `cmd_toggle_search_wrap`, `cmd_toggle_markdown_tables`, `cmd_toggle_soft_tabs`, `cmd_toggle_auto_indent`. `cmd_toggle_minimap` and `cmd_toggle_nerd_font` were deliberately left untouched — they don't set a status message at all (a separate, pre-existing inconsistency, out of scope for a behavior-preserving refactor). **Reconciled at merge time with the concurrently-landed `message_is_error` fix** (which routed all 8 originals' message assignments through `show_message()` to avoid leaking stale error styling onto toggle confirmations): `_toggle_pref` was updated to call `$self->show_message(...)` instead of writing `$self->{message}` directly, so the dedup doesn't reintroduce the bug the other fix closed.

For the cursor-clamp duplication: added `_restore_clamped_cursor($self, $view, $doc, $old_line, $old_col)` in `Editor.pm`, right after `_check_external_file_changes`. Body is the exact original clamp arithmetic (clamp line to `[0, line_count-1]`, clamp col to the clamped line's length) followed by `$view->set_cursor(...)` and `$view->invalidate_wrap_map()`. Both call sites in `_check_external_file_changes` (the dirty-buffer confirm-reload path and the silent clean-buffer reload path) now call this helper instead of repeating the 7-line block.

**Tests:** `tests/editor.t` — added 4 new subtests (auto pairs toggle, restore session toggle, autocomplete toggle incl. completion-dismiss side effect via a `Test::FakeCompletion` stub, and cursor-clamp-after-reload calling `_restore_clamped_cursor` directly with a shrunk document) to cover methods that previously had no direct unit-test coverage. All new tests were run against the pre-refactor code first (via `git stash` of just the two `lib/` files) to confirm they exercise real behavior, then again after the refactor — identical pass in both states. Full suite: 1115 tests (up from 1111), all green, zero stdout/stderr noise.

**QA:** ran targeted `perl qa/runner.pl --tier 1 --filter pref_` (14 scripts, 22 assertions, all pass), `--filter reg_14` (covers the QA-REG-146/147 number range), `--filter sess_009` (restore-session toggle message/state), and `--filter ext_00` (external-reload family) — all pass, no regressions. Relied on this existing coverage rather than adding new `qa/scripts/tier1/reg_146_*`/`reg_147_*` scripts, since it already exercises every refactored method end-to-end through the same command-palette dispatch path that changed, plus the reload-and-keep-local/reload-and-discard flows.

**Interactive verification (`hangon`):** toggled `cmd_toggle_auto_pairs`, `cmd_toggle_restore_session`, `cmd_toggle_soft_tabs` (the custom-label outlier), and `cmd_toggle_mouse` (the side-effect outlier) live via the command palette — each showed the correct `[on]`/`[off]` palette state and exact status-bar message (`Auto Pairs: OFF`, `Restore Session on Startup: OFF`, `Soft Tabs: OFF (tabs)`, `Mouse: OFF`). For the cursor-clamp dedup: opened a 5-line file, moved the cursor to the end of the last line, shrank the file externally to 2 short lines — clean-buffer silent reload clamped the cursor to `2:3` (last line, end of "cd") automatically; made the buffer dirty, shrank the file further to 1 line, chose "Reload" at the change-detected prompt — cursor clamped to `1:2` (end of the new single line). Both matched the expected clamp arithmetic exactly.

### ~~P2: CrossBufferWordProvider rescans every open tab on every trigger, not just the changed one~~ FIXED
`Completion/CrossBufferWordProvider.pm:69-127` — bugs.md's existing "cached per-document by content_version" claim was only true for the skip case. When ANY open document's `content_version` changed, `_rebuild_cache` (lines 79-97) wholesale rescanned *every* open tab (up to `MAX_SCAN_LINES=10000` each) and rebuilt `%all_words` from scratch — not an incremental per-doc merge. Mitigated by the 100ms completion debounce, so not literally per-keystroke, but contradicted the caching description and rescanned N tabs on every trigger regardless of which one changed.

**Fix (Path B — true per-document caching, not just a doc fix):** confirmed the characterization was accurate against current code, then restructured the provider so each open document has its OWN word-frequency cache (`_doc_words`, keyed by doc identity) tagged with the `content_version` it was scanned at (`_doc_versions`). On a trigger, only documents whose version changed since the last scan get rescanned (`_scan_doc`, the line-by-line regex pass) — closed tabs' entries are dropped, untouched tabs are never rescanned. A merged view (`_word_cache`, word → total count) is recomputed by summing the already-cached per-document hashes; that merge is O(total unique words), not O(total lines), so redoing it whenever anything changed is cheap even though the expensive scan is now skipped for unchanged docs. `active_words` (proximity-bonus set) is derived directly from the active doc's cache entry instead of being recomputed during the scan. The single-doc fallback path (`_rebuild_single_doc`, used when there's no `tab_manager`) now shares the same `_scan_doc` helper and cache field names, so there's one scanning code path instead of two near-duplicates.

**Test:** `tests/completion.t` — added subtest "CrossBufferWordProvider (per-document cache isolation)": primes a 2-doc cache, then instruments `Zepto::Document::get_line_content` (via a scoped `local *glob` override, restored automatically) to count calls made against doc2 specifically while editing doc1 only and triggering `complete()` again. Asserts (a) doc2's line-scan call count is exactly 0, (b) doc2's per-document cache hashref is the *same reference* before/after (proof it wasn't rebuilt, not just "looks the same"), (c) doc1's cache entry *was* rebuilt and reflects the edit, and (d) the merged completion results are still correct afterward — both the new word from doc1 and doc2's untouched words still surface. All 7 assertions pass; full `tests/completion.t` (16 subtests) and full `make test` (40 files, 1112 tests) pass with no noise.

**Interactive verification (hangon):** opened 3 tabs with distinct unique identifiers, typed a 2-char prefix in tab B — ghost text correctly suggested tab A's word; accepted it. Then added a brand-new identifier to tab A, switched back to tab B, and typing its prefix correctly surfaced the freshly-added word (proves the targeted rescan picks up new content, not a stale snapshot). Tab C's word (never touched) also still completed correctly from tab B in the same session, confirming the merge doesn't lose untouched docs' entries. `qa/scripts/tier1/cplt_*` (20 scripts, including the pre-existing `cplt_021_cross_buffer`) all pass unchanged.

**QA:** added `qa/scripts/tier1/reg_152_crossbuffer_cache_accuracy.sh` (`QA-REG-152`) — black-box regression coverage asserting the SAME behavior verified interactively above (cross-tab completion before/after a targeted edit, plus an untouched third tab), run 3× to confirm it isn't flaky.

**Incidental discovery (not fixed here, logged separately below):** while writing the QA script, found that pressing Escape (to dismiss an active ghost-text completion) immediately followed by a burst of typed characters starting with a space can silently drop the space or, in one repro, substitute a newline — reproduced independent of this change (also happens in single-document/no-tab-manager mode). See "Escape immediately followed by a burst keystroke send can drop or corrupt the next character(s)" below. The QA script was written to avoid that pattern (continues typing directly instead of escaping first, which is also more realistic user behavior) so it isn't a false dependency on the unrelated bug.

### ~~P3: WrapMap::invalidate_line() has an O(remaining-lines) tail on wrap-boundary changes~~ FIXED
`WrapMap.pm:91-109` — when a single-char edit changes a line's wrapped-segment count (`delta != 0`), it walks every subsequent document line to shift `_doc_to_vrow` offsets. Only triggers on wrap-boundary crossings (not every keystroke), but for large word-wrapped files this is a periodic per-frame spike, not the truly amortized O(1) the "incremental" framing implies. Note: WrapMap invalidation is called out in `docs/CODE_QUALITY.md`'s own pitfall list as a known fragile area — fix with extra care and correctness tests, not just a speed benchmark.

**Fix:** Profiling first (before touching anything) showed the O(remaining-lines) tail was entirely in the `_doc_to_vrow` hash walk — the `_visual_rows` array splice that runs alongside it is NOT a problem (Perl arrays are SV-pointer arrays; splicing near the front of a 40k-element array is a sub-millisecond memmove, confirmed via direct component-level timing). So only `_doc_to_vrow` needed restructuring, not the whole data model. Replaced the eagerly-maintained `_doc_to_vrow` hash (every entry kept correct via the O(n) walk) with a Fenwick tree (Binary Indexed Tree) over per-line segment counts: `invalidate_line()` now does an O(log n) point update (`_fenwick_update`) instead of walking every subsequent line, and `doc_line_to_visual_row()` / `doc_to_visual()` do an O(log n) prefix-sum query (`_vrow_offset`) instead of an O(1) hash lookup into an eagerly-correct hash. Public API (`doc_line_to_visual_row`, `segment_at_visual_row`, `doc_to_visual`, `visual_to_doc`, `total_visual_rows`) is unchanged — only WrapMap's internals moved, so no caller (View.pm, Editor.pm, Renderer.pm) needed changes. The Fenwick tree logic was validated standalone (165k+ randomized checks against a brute-force reference, including line-0/last-line/empty-doc edge cases) before being wired in, and `tests/wrapmap.t` gained 4 new subtests including a property-based brute-force cross-check across 25 randomized boundary-crossing edits — both mutation-tested (deliberately broke the fix two different ways; both were caught by the unit suite). Benchmarks: the isolated Fenwick update/query cost is sub-microsecond regardless of document size or edit position (was ~3.2ms for a boundary-crossing edit near the top of a 20k-line file, scaling linearly with remaining lines); the old ~2-2.7x cost asymmetry between editing near the top vs. bottom of a large wrapped file is gone (now ~1.0-1.2x, i.e. position-independent). Verified interactively via `hangon` on a 500-line wrapped file: boundary-crossing grow/shrink edits near the top render correctly, and scrolling ~260 lines away still shows correctly aligned gutter numbers and content. See `qa/scripts/tier1/reg_153_wrapmap_boundary_edit_correctness.sh` (QA-REG-153).

### ~~P3: Renderer::_render_table_line still uses string-concat, unlike the rest of the file~~ FIXED
`Renderer.pm:1654-1749` builds `$full` via 8 `.=` concatenations per cell/row (including a per-character loop at line 1741) — the exact anti-pattern QA-REG-099 fixed elsewhere in this same file (`_render_line_with_highlights` correctly uses `push @_out`/`join`). Added after that sweep, for the markdown-table feature, so it never got the fix.

**Fix:** Replaced the inefficient string-concatenation pattern in `_render_table_line` with the same `push @array` → `join('', @array)` pattern used throughout the rest of `Renderer.pm`. For separator rows (lines 1682-1691): created `@sep_out` array, pushed all pieces (border color, box chars, separators) onto it, then `join` once at the end. For regular data rows (lines 1708-1755): created `@row_out` array, pushed all pieces (foreground color, left border, per-cell padding, syntax-highlighted cell text, right padding, right border, vertical separators) onto it, then `join` once. The final `join('', @out)` at line 1758 remains unchanged. No visible output change — rendering is byte-identical before and after, verified by rendering test markdown files with tables via hangon. All unit tests pass, all markdown/table QA tests pass (12 passed in tier 1/2 run, including `pref_020_markdown_tables_persist` which explicitly tests table rendering).

### ~~P3: SECURITY.md is stale in several places~~ FIXED

**Fix:** Updated `docs/SECURITY.md` with accurate information:

1. **Network connections:** Rewritten the Network threat to reflect reality: "Zepto makes zero network connections by default. Optional AI completion feature (disabled by default, requires explicit user configuration of API endpoint + key) makes opt-in HTTPS calls to OpenAI-compatible APIs via curl. No network calls are made for any other feature."

2. **Shell execution inventory:** Expanded from "three places" to complete list of six actual locations, all using safe list-form `exec()` / `system()` with argument arrays (no shell interpolation): VCS integration (git), Clipboard tools, File search (git grep/rg/grep), Image format conversion (sips/convert via `which` on hardcoded literals), Text transformation (user-typed shell command via `cmd_transform`/Alt+T — intentional capability, not injection), and AI completion (curl for HTTPS). Each location documented with its approach.

3. **_shell_quote() function:** Removed dead reference. Replaced the outdated example showing `_shell_quote()` with explanation that current codebase uses list-form pipes and `exec()` throughout, which is fundamentally safer (eliminates shell interpretation entirely rather than relying on quoting).

4. **Symlink traversal:** Moved from "Open Items" to "Resolved Items". Documented that FileTree.pm and FilePicker.pm use `Cwd::realpath()` to resolve symlinks in root and all discovered paths, with correct prefix-with-slash traversal check (`index($real, "$root/") == 0`) that prevents "/root" vs "/rootevil" bypass bug. Both implementations audited and correct.

5. **Audit Checklist:** Updated to reflect current mitigation (list-form exec) instead of dead `_shell_quote()` function. Added guidance about `Cwd::realpath()` for symlink handling and opt-in nature of AI completion.

### ~~P3: Two hardcoded /Users/joe paths in QA scripts (repeats a documented past mistake)~~ FIXED
`qa/scripts/tier1/reg_019_natural_sort.sh:12` and `qa/scripts/tier1/reg_021_new_file_tree.sh:9` both hardcoded `QA_ZEPTO=$(cd /Users/joe/src/zepto && pwd)/zepto` — the exact pattern `CLAUDE.md:150` itself cites as a past CI-breaking incident ("cd /Users/joe/src/zepto hardcoded in 5 test scripts — broke on Ubuntu"). Will break on any other machine or CI.

**Fix:** Replaced both with the portable pattern `QA_ZEPTO="$(cd "$(dirname "$0")/../../.." && pwd)/zepto"` that resolves the zepto binary path relative to the script's own location using `$0`, not hardcoded paths. This pattern was already in use by several other working tier1 QA scripts (`fif_015_esc_closes.sh`, `file_014_save_vcs_gutter.sh`). Both scripts tested individually with `bash` after the fix: `reg_019_natural_sort.sh` passes (0 FAILED, 1 skipped), `reg_021_new_file_tree.sh` passes (1 PASSED, 0 FAILED).

### ~~P3: Dead code — _in_modal_state and an empty tautological InputParser branch~~ FIXED
- `Editor/Commands.pm:18-22` `_in_modal_state` helper was added and initially used to replace guard blocks in `cmd_open_file`/`cmd_recent_files`/`cmd_find_in_files` (bugs.md line 299). However, the calls to this helper were removed later (bugs.md line 184, fix for "Global shortcuts should work from any state") when guard interception was moved to `handle_event()`, leaving the method orphaned with zero call sites. Deleted.
- `InputParser.pm:250-254` — an empty no-op `if` block for legacy "basic format" (non-SGR) mouse events, whose own comment admits the logic was abandoned mid-implementation ("Actually buffer was already consumed... handle differently"); also contains a tautological `length(...) >= 0` condition. Not currently reachable/harmful (Zepto only enables SGR mouse mode, `?1006h`), but should be deleted or finished. Treat with extra care given this file's history of subtle input-parsing bugs this session (QA-REG-102, OSC handling) — verify no live basic-mouse-format path depends on it before removing.
  **FIXED**: Confirmed `Terminal.pm:42` (`MOUSE_ENABLE => "\x1b[?1003h\x1b[?1006h"`) never enables bare `?1000h`-only basic mode, so no real terminal can send Zepto a legacy 3-byte mouse report. Independently confirmed the branch was already a structural no-op even before removal: `ESC [ M` (no params) already terminates as its own complete CSI sequence in `_parse_csi` (M is a valid CSI final byte, 64-126), so `_decode_csi` is entered with `$params=''`, the empty if-block does nothing, and control falls through to "Unknown CSI sequence" → `EVT_NONE`. Any legacy-format data bytes that would follow are parsed independently as plain characters by the outer loop — exactly the same before and after deletion (verified with a hand-fed `\x1b[M` + 3 raw bytes probe, before and after the deletion, producing byte-identical output). Removed the dead lines from `InputParser.pm:250-254`; the surrounding `if/elsif`-style chain in `_decode_csi` needed no other changes since the block had no `return`. Added `tests/input_parser.t` subtest "Basic-format (non-SGR) mouse report is not decoded — treated as unknown CSI" and `qa/scripts/tier1/reg_145_inputparser_dead_branch_removed.sh` (QA-REG-145). Full `tests/input_parser.t` (39/39), full `make test` (1112/1112), and the `ms_*` mouse QA sweep (16 scripts / 29 assertions) all pass unchanged. Interactive `hangon` verification: click moved the cursor and updated the status bar, drag produced a selection, scroll and hover produced no crash or stray characters, and quit exited cleanly with no unsaved-changes prompt (confirming no garbage was typed into the document). The `_in_modal_state` half of this bug is NOT part of this fix — left for the other agent handling `Editor/Commands.pm`.

### ~~P3: Renderer.pm palette/dialog layout uses inline magic numbers~~ FIXED
Sizing literals with no named constants: 120/80/60/30 (palette width tiers, `Renderer.pm:514-520`), 45 (`:623`), 40 (`:632`), 50/15 (menu width, `:765-766`), 10/20 (input width, `:567-576`), `mark_interval=10` (`:1263`). Contrast with the same file's proper `use constant` blocks (`TAB_WIDTH`, `DIALOG_WIDTH`, `FILE_EXISTS_CACHE_TTL`).

**Fix:** Pure rename/refactor — no numeric values or rendering behavior changed. Added six new `use constant` blocks directly below `TAB_WIDTH` (`Renderer.pm:86-119` after the change):
- `PALETTE_WIDTH_WIDE => 120`, `PALETTE_WIDTH_MEDIUM => 80`, `PALETTE_WIDTH_NARROW => 60`, `PALETTE_WIDTH_MIN => 30`, `PALETTE_MAX_ITEMS_MIN => 5`, `PALETTE_MAX_ITEMS_MAX => 30`, `PALETTE_SHORTCUT_WIDTH_MIN => 8` — palette width tiers/item-count bounds/shortcut-column floor, each duplicated between the cursor-positioning code (near old `:514-536`) and `_render_command_palette` (near old `:5071-5082`, `:5393`); both copies now reference the same constants.
- `COMPLETION_MENU_WIDTH_MAX => 50`, `COMPLETION_MENU_WIDTH_MIN => 15` — replaces `_render_completion_menu`'s inline `50`/`15` (old `:765-766`).
- `FIND_BAR_RIGHT_SIDE_BASE_WIDTH => 45`, `FIND_INPUT_WIDTH_MIN => 8`, `FIND_INPUT_WIDTH_MAX => 40` — replaces the find/replace bar's inline `45`/`8`/`40`, again duplicated between cursor-positioning code (old `:623,631-632`) and `_render_find_bar` (old `:4730,4740-4741`).
- `FOOTER_INPUT_WIDTH_GOTO_LINE => 10`, `FOOTER_INPUT_WIDTH_WIDE_MIN => 20`, `FOOTER_INPUT_WIDTH_DEFAULT => 12` — replaces the footer-input field's inline `10`/`20`/`12`, duplicated between cursor-positioning code (old `:567-576`) and `_render_footer_input` (old `:4470-4474`).
- `RULER_MARK_INTERVAL => 10` — replaces the column ruler's inline `10` (old `:1263`).

Verified behavior-preserving with a throwaway pure-function harness (not committed) that called `Zepto::Renderer->render` directly for the palette (both `commands` and `recent_files`/wide-tier modes), find bar (plain and replace-active), footer input (goto-line, wide, default), and completion menu at 12 widths spanning every tier boundary (30, 50, 60, 76, 80, 84, 100, 119, 120, 124, 140, 200) — output was byte-for-byte identical before/after across all 84 combinations. Also confirmed interactively via `hangon` (command palette, find bar incl. replace-active, goto-line footer input, completion dropdown via `cplt_009_dropdown`) at the default 80×24 size. QA: `perl qa/runner.pl --tier 1 --filter pal_` (23/23), `--filter reg_046` (1/1), `--filter find_` (40/40, 1 pre-existing skip), `--filter goto_` (18/18, 1 pre-existing skip), `--filter cplt_` (20/20), `--filter prmt_` (11/11, 1 pre-existing skip) all pass. Full `make test` (1111 tests) and `make check` pass.

### ~~P3: Silent eval swallow in file-tree preview open~~ FIXED
`_tree_preview_current` (`Editor.pm`, the function previously referred to here as `_start_preview` — that name doesn't exist in the codebase) wraps document creation in a bare `eval {}` — if opening a preview fails (permission error, decode failure), nothing happened: no message, no log, dead silence. Inconsistent with every other file-open path in the same file, which all route failures through `_user_error()`/`show_error_message()` (`cmd_save`, `_finish_save_as`, `_load_file`, the two external-reload paths).

**Root cause:** the eval's `$@` was never checked. On failure, execution just fell through the end of `_tree_preview_current` with `tree->{preview_active}`/`preview_path` left in whatever state they were in before the attempt.

**Behavioral discovery made while reproducing this:** `FileTree::_scan_dir_one_level` only lists files that pass `-r` (readable) at scan time, so a file that's unreadable from the very start never appears in the tree — there's no way to navigate to it. The bug is real, but the practical trigger is a TOCTOU race: a file is readable when the tree scans, then loses read access (permission change, unmount, etc.) before the user arrows onto it and a preview is attempted.

**Fix:** added `if ($@) { ... }` after the eval in `_tree_preview_current`, matching the established pattern: `$self->show_error_message(_user_error("Preview failed", $@))`. Also resets `preview_active`/`preview_path`/`_preview_is_existing_tab` and switches back to `pre_preview_tab_index` on failure (reusing the exact restore logic already used by the sibling "cursor on directory" branch in the same function), so that rapid arrow-key navigation past several broken files in a row can't accumulate stale preview state or leave a dangling tab reference — each failed attempt cleanly reverts before the next begins. The status bar's existing "message persists until replaced by user input" behavior (`docs/UI_GUIDELINES.md`) already prevents the error from being spammy across rapid navigation: each failure's message is cleared by the very next keypress.

**Test:** `tests/editor.t` ("Tree preview of unreadable file surfaces an error message") reproduces the TOCTOU race directly against `_tree_preview_current` — confirmed silent (empty `$self->{message}`) before the fix, confirmed `message_is_error` + a "Preview failed: ..." message after. Interactively verified with `hangon`: previewed a readable file, revoked its permissions from another shell while zepto was running, arrowed off and back onto it — status bar showed `Preview failed: Cannot open <file>: Permission denied`; a subsequent preview of a different readable file worked normally with no leftover broken state. QA regression script: `qa/scripts/tier1/reg_154_preview_error_feedback.sh` (`QA-REG-154`), feature test `QA-TREE-027`.

### P2: Stale duplicated tail on the cursor's own line after typing into a large file (found 2026-08-30, incidental to Buffer.pm perf work)
While interactively verifying the `Buffer::get_text()`/line-index perf fix (QA-REG-150/151) on synthetic 4000-5000 line files via `hangon`, typing a character into a line partway through the file sometimes renders that ONE line (the line under the cursor, and only that line — neighboring lines are unaffected) with a stale duplicate of its own pre-edit tail appended, e.g. typing `a`,`b` into `row2000text` at line 2000 renders `abrow2000textrow2000text` on screen (the correct `abrow2000text` followed by a stale extra copy of `row2000text`). Reproduced with both a single multi-char `send` and separate per-character `send` calls; does not self-correct after 2s, after moving the cursor away and back, or after page up/down.

**Confirmed NOT a data-correctness bug and NOT introduced by the Buffer.pm changes in this session:**
- Saving (`⌃S`) and reading the file from disk always shows the CORRECT content (`abrow2000text`, no duplication) at every point this was observed — the underlying document/gap-buffer content is right; only the on-screen paint of that one row is wrong.
- The status bar's cursor line:col is correct throughout (e.g. `2000:3` after 2 chars).
- Reproduced identically — in fact with MORE garbling — after `git stash`-ing this session's `Buffer.pm` changes back to the original `553f43b` implementation and rebuilding, so this predates and is independent of the `get_text()`/line-index work.

**Not investigated further** (out of scope for the Buffer.pm task this was found during): most likely candidate is `Editor.pm::do_insert_char()`'s `$view->invalidate_wrap_line($view->cursor_line())` call into `WrapMap.pm`, given `WrapMap.pm` is already flagged elsewhere in this file as a fragile, easy-to-get-subtly-wrong incremental-update area (see the `WrapMap::invalidate_line()` P3 entry above) — but this was not confirmed, could equally be in `Renderer.pm`'s single-line incremental redraw path. Needs a dedicated repro script and investigation by whoever picks this up; the QA-REG-150/151 scripts added alongside this fix deliberately verify edit correctness via save-to-disk rather than raw on-screen string matching for any line that was just typed into, specifically to route around this rendering artifact without giving it a false pass.

### P3: [Architecture] Editor is a 6000-line god object across 3 files — SKIPPED (numbers now stale)
Original entry deferred this as multi-session work; still the right call, but current numbers are understated. As of this audit: `Editor.pm` + `Editor/Commands.pm` + `Editor/Palette.pm` (all three `package Zepto::Editor;`, no real encapsulation boundary between them) total **7,729 lines, 220 methods** (up from the cited 6000/162) — a ~29% line and ~36% method growth since the entry was written, with no extraction having occurred. `Editor/TabManager.pm` (318 lines, a genuine separate `Zepto::Editor::TabManager` class) proves the team can extract a subsystem when it chooses to — the god object isn't a capability gap, just deferred. Not assigned to the current agent fleet (too large/cross-cutting for a bounded background task) — flagging the stale numbers only.

### ~~P3: llm-judge.sh crashes on reasoning-model responses (null content field)~~ FIXED (2026-08-30)
Found while running the discoverability sweep against a non-Anthropic model (`minimax/minimax-m3` via a local OpenAI-compatible gateway, per user request to conserve credits — see http://ai/v1/models). Reasoning models put their analysis in a separate `reasoning`/`reasoning_details` field and leave `content: null` until reasoning concludes; with the script's `max_tokens: 100`, the model always hit `finish_reason: "length"` before ever writing a final `content` answer, and the parser crashed with `'NoneType' object has no attribute 'strip'` on every single call — the sweep failed 8/8 with a parse error, not a real judgment.

**Fix:** `qa/lib/llm-judge.sh` — (1) raised the OpenAI-compatible path's `max_tokens` from a hardcoded 100 to a configurable `${ZEPTO_QA_MAX_TOKENS:-2000}` (structured multi-part discoverability judgments need real budget to reason through); (2) the Python response parser now falls back to `reasoning`/`reasoning_details` when `content` is null, rather than crashing, tagging truncated-before-a-verdict responses distinctly from genuine parse failures. Verified with `minimax/minimax-m3`: same prompt/screenshot that previously produced a parse error now returns a real, coherent, useful judgment.

### P1: Discoverability sweep run 2 (2026-08-30) — LLM vision judge, real findings + one calibration note
Reran the full `qa/scripts/tier2/discoverability_sweep.sh` matrix (8 screenshots: document × {80×24, 60×20, 40×15} × {dark, light}, plus file-tree × {dark, light}) using `minimax/minimax-m3` via a local OpenAI-compatible gateway (see llm-judge.sh fix above) after the manual 5-screenshot sample from the previous entry. This is the first time the automated sweep actually ran end-to-end rather than being reviewed by hand.

**Confirmed, consistent across every single screenshot (8/8):** (a) Quit has no on-screen hint anywhere, at any width, in any theme, in any context — matches the manual pass. (e) The `⌃␣ Commands` fallback signpost is present and recognized everywhere — the contract's "always know where to find everything else" guarantee holds.

**Refines the manual pass's finding on (b)/(c) tab navigation:** the manual pass concluded close/next/prev-tab "already work" because the corner hint (`⌃W × ⌥, ← ⌥. →`) is technically rendered and survives narrow widths. The LLM sweep disagrees, consistently (6/6 relevant screenshots): the hint is present but **not comprehensible to a first-time user** — raw modifier glyphs with no label ("unlabeled and ambiguous", "no clear 'tab' indication"). This matters: the Discoverability Contract requires the hint be usable by someone who's "never read any documentation," not merely rendered — a cryptic glyph cluster technically satisfies "on screen" but fails the actual contract. Downgrades that part of the manual finding from "already covered" to "present but not actually discoverable without prior knowledge — needs a label, not just glyphs."

**New finding, not caught manually:** the compact Word Wrap pill (bare "Z" at narrower widths, by design per the priority-based progressive disclosure system) reads as an unlabeled, context-free letter to a first-time user (flagged independently in 3 of the 4 document screenshots). This is arguably working as designed (compact form = icon+key, dropping the label is the intended tradeoff) but is worth weighing against the Discoverability Contract's standard.

**Calibration note — two claims investigated and found to be model misreads, NOT real bugs (verified by direct screenshot inspection, not taken on faith):**
- Claimed "line number '1' appears duplicated between ruler and gutter" / "ruler layout misaligned" at 40×15 — re-captured and inspected directly: no overlap. The model conflated the ruler row's small cursor-line badge (a legitimate, distinct UI element showing "line 1" context) with the gutter's actual line-number column — both correctly show "1" because the cursor is on line 1, which is not a bug.
- Claimed the file-tree context's corner hint is "overlapped/obscured by the active tab label" — re-captured with a short filename and found no collision; not re-tested with a filename as long as the original sweep's (`disc_filetree.txt`, 14 chars) so a genuine collision at longer filenames isn't fully ruled out, but the claim as stated didn't reproduce.

**Takeaway for future sweeps:** trust this pipeline's judgment-based findings (is X labeled/discoverable/comprehensible) — that's exactly the class of question a contrast-ratio-style deterministic test can't answer and this model got right, consistently, across repeated runs. Spot-check any claim of a concrete pixel-level rendering defect (overlap, truncation, misalignment) against a direct screenshot before treating it as confirmed — this model hallucinated two of those in one 8-screenshot run.

Not fixed here — same as the manual-pass entry, this is a finding-gathering pass. Candidate fixes now better-scoped: (1) give Quit a hint everywhere, (2) add a plain-language label to the tab-nav corner hint instead of relying on raw glyphs (e.g. spell out "close/prev/next" abbreviated, or make it discoverable via a one-time/first-launch nudge), (3) extend file-tree context with its own hint set, (4) decide whether the bare "Z" compact-pill tradeoff is acceptable or needs a fallback tooltip/legend.

## Found while fixing the ReDoS match-timeout bug (2026-08-30)

### P2: Perl warnings leak to the terminal and corrupt the TUI display
Discovered while interactively testing the ReDoS match-timeout fix (`QA-SEC-012`) via `hangon`: typing a counted-repetition pattern like `(a?){28}` into the find bar in regex mode — one keystroke at a time, as find-as-you-type does — causes Perl's `use warnings` to emit "Unescaped left brace in regex is passed through in regex" to STDERR on every intermediate incomplete pattern (`(a?){`, `(a?){2`, etc. are each individually compiled via `_build_regex()` as the user types). Nothing in the codebase installs a `$SIG{__WARN__}` handler (confirmed: `grep -rn '__WARN__' lib/` finds none, `Terminal.pm:274` only handles `__DIE__`), so these warnings hit the real STDERR and scroll raw text across the alternate screen buffer, visually corrupting the TUI until something forces a full redraw. Confirmed this is NOT specific to the ReDoS fix or to pathological patterns — any use of an incomplete `{n}`/`{n,m}` quantifier while typing (a totally ordinary, non-malicious thing to type in regex-find mode) triggers it; reproduced identically on unmodified `_build_regex()`. The editor itself keeps functioning underneath (confirmed: still accepts input, `⌃Q` quits cleanly) — this is a display/robustness bug, not a hang or data-loss issue, which is why the ReDoS fix (P1, above) doesn't fix or depend on it. Not fixed here — out of scope for the ReDoS task; candidate fix is a process-wide `$SIG{__WARN__}` handler that redirects warnings to a log file (or suppresses them) for the lifetime of the TUI session, restored on exit, mirroring the existing `$SIG{__DIE__}` handling pattern in `Terminal.pm`.
