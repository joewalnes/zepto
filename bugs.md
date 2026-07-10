# Bugs

Priority scale:
- **P0**: Broken core functionality — data loss, crash, or fundamentally wrong behavior.
- **P1**: Significant usability issue — feature works but is confusing or misleading.
- **P2**: Polish issue — inconsistency, visual glitch, or minor misbehavior.
- **P3**: Cosmetic / edge case — low impact, fix when convenient.

Format: each entry is `### P#: Title`. Closed entries (fixed, skipped,
won't-fix, or superseded) have moved to `bugs-archive.md` — this file is
the currently-open worklist plus the active testing-hazard notes that QA
scripts need to route around. When a bug here is fixed, move its entry to
`bugs-archive.md` with a **Fix:** note rather than deleting it.

---

## Open bugs

### P3: Regex mode defaults to ON in find bar

The find bar starts with regex mode enabled by default. Most editors (VS Code, Sublime, etc.) default to literal search. This means typing `foo.bar` matches `fooXbar` on first use, which is unexpected for most users. Toggle with ⌃R. Confirmed via QA-FIND-009.

### P3: No "Save As" command in palette

The command palette has "Save" (⌃S) and "Save and Close Tab" (⌃W) but no "Save As" / "Save to different location" command. File→Save As is a standard editor operation. Users can only save to the original path.

### P3: Transform (Alt+T) is shell-pipe only

The transform feature (Alt+T) opens a shell command prompt. There are no built-in text transforms (uppercase, lowercase, sort, etc.) — users must type shell commands like `tr '[:lower:]' '[:upper:]'` or `sort`. This works but is not discoverable for users unfamiliar with Unix pipes.

### P2: Ruler cursor-column indicator partially overwrites tick labels

The gutter/ruler's cursor-column indicator can render on top of the ruler's tick-mark labels instead of replacing or spacing around them cleanly. For example, at column 18 the ruler renders `18 0` where the tick label `|20` was expected — the cursor-column digits and the tick label digits are interleaved/overlapping rather than one cleanly taking precedence, producing garbled output instead of either label.

### P2: Open File picker — Enter on a non-matching absolute path outside cwd is a silent no-op

In the Open File picker (⌃O), typing an absolute path that lies outside the current project root and that matches no discovered files, then pressing Enter, does nothing: no error message, no "file not found", and no offer to create a new file at that path. The user gets no feedback that their input was rejected and no indication of what to do next.

### P2: [Bug] Horizontal scroll can snap to a huge offset after column paste, leaving stale trailing screen content

After a column paste onto the last line of a short document, pressing `End` (or, per `qa/scripts/tier1/clip_007_column_paste.sh` history, even without pressing anything extra) can cause the viewport's horizontal scroll to jump to a very large column offset (observed: ruler showing `90` as the leftmost visible tick for a 12-character line) even though the actual line content is short. The underlying document/file content is correct — verified via save+reload — but the tmux/terminal screen capture at that point shows truncated, stale trailing characters for the row (e.g. `aaaadddd` instead of `aaaadddd4444`), suggesting the row isn't being fully redrawn/cleared after the scroll-offset jump. Reproduce: open a 4-line file, column-select+copy 3 rows x 4 cols from rows 1-3, move to line 4 col 1, paste, press End. Not yet root-caused past this point (likely a stale/incorrect horizontal-scroll calculation seeded by the column-mode selection's rightmost column). QA-CLIP-007 and QA-COL-004 route around it by asserting on the saved file instead of the screen.

---

## Feature requests

### P1: Status bar rework — always-visible keys grouped by modifier

The status bar should make keyboard shortcuts always visible and organized by modifier key, similar to Zellij's approach. Group `⌃` (Ctrl) shortcuts on the left and `⌥` (Alt) shortcuts on the right, so the modifier is shown once per group rather than repeated on every pill — saving space and making the modifier split immediately clear. Buttons should be contextual, showing what's most relevant to the current state (e.g., editing vs find mode vs file tree). Currently, pills are arranged by category (FILE/EDIT/NAVIGATE/VIEW from `CommandRegistry::commands_for_status_bar`) with each pill repeating its modifier, and lower-priority pills drop off at narrow widths. The rework should ensure the most useful actions are always visible regardless of terminal width.

### P3: Dim Markdown formatting delimiters

In Markdown files, emphasis delimiters (`**`, `*`, `_`, `~~`, `==`) are rendered as `TOKEN_PUNCTUATION` in `Syntax/Markdown.pm`, giving them the same visual weight as the styled text they surround. The delimiters should be rendered much fainter (dimmed/low-opacity) so the bold, italic, strikethrough, and highlighted text pops out visually. This is how many modern Markdown editors handle it — the formatting chars become near-invisible while the styled content stands out. Currently all delimiter tokens share the generic punctuation color in `Theme.pm`.

### P2: Session restore

Reopen the editor and get back exactly where you were: same tabs, cursor positions, scroll positions. The recent files infrastructure already exists (`~/.config/zepto/recent_files`). Extending to full session state eliminates the re-navigation tax every time the editor is restarted. Especially important for a terminal editor that gets opened/closed frequently.

### P2: Shortcut key for Duplicate Down

Duplicate Down currently has no keyboard shortcut — it's palette-only. Should have a direct keybinding for quick access. `⌃D` is taken (Select Next Occurrence). Candidates: `⌃⇧D` (Shift=reverse already used for Duplicate Up as `⌃U`, but `⌃⇧D` is intuitive as "duplicate" with Shift for the pair), or find another mnemonic. Also consider giving Duplicate Up a matching shortcut if it doesn't have one.

### P3: Automatic dark/light mode

Detect the system theme (dark/light) on startup and choose the matching editor theme. Detect when the system theme changes at runtime and automatically switch. Auto mode is optional — users can still manually set dark or light via `Ctrl+T` or config.

### P3: Multi-line matches not fully supported in find/replace preview

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. The live replacement preview (green highlight of what text would look like after Replace All) does not fully handle matches that span multiple lines.

### P3: Incremental replace (one match at a time) not implemented

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. Replace currently only supports "Replace All" — there is no way to step through matches and replace them one at a time, confirming or skipping each.

### P3: Replace with confirmation not implemented

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. No "are you sure" / per-match confirmation step before Replace All mutates the document.

### P3: Find in selection not implemented

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. Find/replace always searches the whole document; there's no way to scope a search to the current selection.

### P3: Whole word matching option not implemented

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. No toggle to match whole words only (e.g. searching `cat` matching `cat` but not `category`) outside of writing a regex with `\b` manually.

### P3: Search history not implemented

From `docs/FIND_REPLACE_SPEC.md`'s Known Issues list. Previous find/replace queries are not remembered across sessions or even within a session once the find bar closes.

---

## Testing hazards (active)

Notes about the QA harness (`hangon`, tmux, timing) that are not Zepto product bugs but affect how tests must be written. Keep these active — do not archive — until the underlying tool/timing issue is actually resolved.

### P3: Preference state persists between sessions

Toggle states (minimap, word wrap, nerd font, etc.) persist to preferences. This means QA tests that toggle features can affect subsequent tests. Tests must save and restore state. Not a bug per se, but a testing hazard worth documenting.

### P3: [Testing hazard] `hangon`'s shared state.json is not written atomically — races under parallel QA runs

Found alongside the env-laundering bug above (initially misdiagnosed as the whole story behind QA-EDIT-020's baseline failure — it's real, but it was only a secondary contributor). `hangon`'s session registry at `~/.hangon/state.json` (shared across every concurrently-running `hangon` CLI invocation on the machine) is written with a plain `os.WriteFile` (see `state.go` in the `joewalnes/hangon` Go module), which is not atomic. Under enough concurrent `hangon start`/`stop` calls (e.g. many tier1 scripts launching sessions around the same time under `make qa`), a reader can observe a torn/truncated write and hangon exits nonzero with `corrupt state file ... unexpected end of JSON input` (or transiently `session "NAME" not found`).

This is a bug in the third-party `hangon` binary, not in Zepto — nothing to fix in this repo beyond making the harness resilient to it. **Mitigation:** `qa_start()` in `qa-helpers.sh` retries `hangon start process` up to 3 times (with a short backoff and session cleanup between attempts) before giving up, so a rare torn-write no longer fails an otherwise-passing test.

### [Behavioral discovery] Ctrl+Space is context-sensitive — completion menu when mid-word, command palette otherwise

`Editor.pm` (~1292-1312): pressing Ctrl+Space checks the character immediately before the cursor; if it's a word character (`\w`), Ctrl+Space triggers the completion menu instead of opening the command palette. This is intentional (dual-purpose keybinding), not a bug, but it's non-obvious and bit `qa/scripts/tier1/reg_021_new_file_tree.sh` while fixing that script's hardcoded-path failure: a "type content, then Ctrl+Space, type 'save as', Enter" flow silently typed the literal text "save as" into the document (cursor was right after "content", a word character) instead of invoking the Save As command — no error, no crash, just the wrong thing happening silently. reg_021 now uses `Ctrl+S` instead (equivalent for an untitled buffer, and unambiguous) to sidestep this entirely. Documented and regression-guarded directly by QA-CPLT-021, which exercises both sides of the branch (cursor at col 0 -> palette opens; cursor after a word char -> palette does NOT open).

### [Testing hazard] hangon's mouse-click/mouse-drag SGR inversion is masked for stationary clicks, but breaks every true drag

Follow-up to the QA-MS-012 investigation (see the qa_mouse_press comment block in `qa-helpers.sh`): `hangon`'s `mouse-click`/`mouse-drag` subcommands encode the SGR press/release final byte backwards relative to the xterm standard Zepto's `InputParser` expects. For a **stationary click** (press and release at the same cell — `hangon mouse-click`, or a `hangon mouse-drag` where from==to), this is accidentally harmless: hangon's "press" (sent as lowercase `m`) is misread by Zepto as a release (no-op), and hangon's "release" (sent as uppercase `M`) is misread as a press — which still lands at the correct, single target coordinate, so a plain click still works. That's why the ~25 tier1 scripts that only use single/double/triple *clicks* (`ms_001`, `ms_002`, `ms_004`, `ms_005`, `ms_009`, `ms_010`, `ms_013`, `ms_015`-`017`, `pal_011`, `pal_012`, `pal_021`, `pick_014`, `prmt_006`, `reg_027`, `reg_042`, `reg_097`, `sbar_012`, `tab_015`, `tree_009`, `tree_018`, `gut_002`, etc.) were never in the failing baseline.

For a **true drag** (from != to), the same inversion breaks it: the initial press is dropped (misread as release, so `mouse_button_down` never gets set), the intermediate button-held motion events are then ignored by Zepto's drag handler (`return unless mouse_button_down`), and only the final "release" (misread as a press) fires — at the drag's *end* coordinate only, as a plain click, not a drag. QA-MS-012 (fixed this phase) was the one script where this was caught, because its assertion happened to check the actual mutated state (tree width). `ms_003_drag_select.sh`, `ms_008_alt_drag_column.sh`, and `tree_023_drag_scrollbar.sh` still use `hangon mouse-drag` and likely have the identical latent flaw — not yet confirmed/fixed in this phase (out of scope; flagging for a future pass). Prefer the `qa_mouse_press`/`qa_mouse_drag`/`qa_mouse_release`/`qa_mouse_drag_gesture` helpers in `qa-helpers.sh` (raw SGR injection, bypassing hangon's encoder) for any new or rewritten drag test — see QA-MS-021/QA-MS-022 for examples.

### [Testing hazard] hangon's `send` fails outright on text starting with a hyphen

Discovered while writing QA-EDIT-022 (list continuation), which needs to type Markdown bullets like `- item`. `hangon send SESSION "- item"` — and `hangon send SESSION --stdin` piped the same leading-hyphen bytes — both fail immediately: exit status 2, `exit status 1` printed to stderr, and **nothing is sent to the session** (confirmed with a minimal repro: `hangon send SESSION "-x"` fails but `hangon send SESSION "x-x"` and even a bare `hangon send SESSION "-"` alone both succeed — it's specifically "hyphen followed by more content" that trips it, suggesting hangon's own CLI arg/flag parsing is swallowing it, not a session or PTY issue). A literal `--` end-of-flags marker before the text does not help. Under `qa-helpers.sh`'s `set -euo pipefail`, this silently aborts the ENTIRE calling script the moment it happens — no assertion output, no `qa_fail`, just a dead script and a nonzero exit, which is easy to misdiagnose as a Zepto crash rather than a harness bug.

**Mitigation:** added `qa_send_safe` to `qa-helpers.sh` — types a harmless one-character prefix so the string handed to `hangon send` never starts with `-`, then removes exactly that prefix character via `Left`×N + `Backspace` + `Right`×N (NOT `Home`+`Delete`, which would jump to column 0 and delete the wrong character unless the cursor started at the beginning of the line). Use `qa_send_safe` instead of `qa_send` for any text that might start with `-` (list markers, CLI-flag-like strings, negative numbers, etc.). Used by `qa/scripts/tier1/edit_022_list_continuation.sh`. Not fixed at the source (hangon itself, third-party binary) — flagging for a future pass / upstream report.

### P2: [Testing hazard] `tests/editor.t` writes to the real `~/.config/zepto/` — pre-existing, not isolated

Discovered while adding new `continue_lists`-preference tests (Phase 2 item 5): the vast majority of `tests/editor.t`'s ~90 subtests construct `Zepto::Editor->new(terminal => $term)` **without** an explicit `state_store` override. `Editor::new`'s default is `state_store => $opts{state_store} // Zepto::StateStore->new()` — with no `base_dir`, `StateStore->new()` resolves to the REAL `$XDG_CONFIG_HOME/zepto` (or `~/.config/zepto`), same as a real user's editor. So every one of those subtests reads and can write to the actual persisted preferences/history files on whatever machine runs the test suite. Confirmed pre-existing (reproduces identically on the unmodified `HEAD` commit before any Phase 2 changes, via `git stash` + rerun) — not introduced by this phase, but newly *consequential*: any future test that asserts a preference's *default value* (as two of this phase's new `continue_lists` subtests initially did) is flaky, since the "default" it reads depends on whatever a previous test run — or a developer's own interactive `hangon`/manual testing on the same machine without `--state-dir` — happened to leave persisted. Both new `continue_lists`-default-checking subtests were fixed to use an isolated `Zepto::StateStore->new(base_dir => tempdir())`, following the existing (but inconsistently applied) pattern already used by a handful of other subtests in the same file (e.g. "Recent files" tests). Not fixed project-wide in this phase — would mean touching ~90 subtests across a 1800+ line file, out of scope for the current task and risks unrelated churn. Flagging for a future pass: either default every subtest in this file to an isolated state store, or add a file-level `BEGIN`/setup hook that redirects `$ENV{XDG_CONFIG_HOME}` to a tempdir for the whole test run.

### [Testing hazard] A lone Esc needs more than the default 0.4s QA_RENDER_WAIT under load

While writing the AI Settings dialog QA scripts, `qa_keys "escape"` followed by the default `qa_assert_screen`/`qa_assert_not_screen` (0.4s wait baked into `qa_keys`) intermittently observed the PRE-escape screen state — the dialog (or, reproduced identically against the unmodified command palette, the palette) was still fully visible immediately after Esc. Root-caused via a direct non-interactive harness (`Zepto::Editor->handle_event({type=>'key', key=>'escape', ...})` called directly, bypassing the terminal): the state-machine logic itself is instant and correct (`close_dialog()` runs, state flips immediately) — the delay is entirely in `Zepto::InputParser`, which holds a lone ESC byte pending (`_parse_escape`: `return {type => EVT_NONE}` for a 1-byte buffer) to disambiguate it from the start of an Alt+key sequence, and only resolves it into a real `KEY_ESCAPE` event via `flush_pending` on the main loop's next idle timeout (`INPUT_TIMEOUT_SEC => 0.5`). A capture taken before that timeout fires legitimately shows the pre-Esc screen — not a bug, just a real ~0.5s latency window inherent to unambiguous Esc detection over a raw byte stream. Confirmed NOT specific to the new AI dialog: the identical short-wait timing gap reproduces against the pre-existing, unmodified command palette's Esc-clears-filter/closes behavior too.

**Not a product bug — no code changed.** This is a pre-existing characteristic of every Esc keypress in the app, previously masked in the rest of the QA suite by 0.4s (just under the 0.5s window) usually being *enough* in practice, and evidently more reliably so on less-loaded CI runners than the one this was diagnosed on (a container observed running a second, unrelated concurrent agent's own hangon/tmux QA activity at the time — see the general hangon-contention entries above). **Mitigation:** the new `ai_001`/`ai_003`/`ai_004` QA scripts pass an explicit longer wait to `qa_keys "escape" 1.2` at every Esc that a subsequent assertion depends on, rather than the 0.4s default. Flagging as a general pattern for any *future* QA script whose very next assertion depends on an Esc having taken effect: prefer `qa_keys "escape" 1.2` (or poll) over the bare default.

### [Testing hazard] hangon escape-key delivery on CI

On GitHub Actions runners, `hangon keys escape` intermittently delivers literal caret text `^[` (printable `^` + `[`) to the pane instead of the ESC byte — near-deterministic on CI (persists in serial no-load retry), unreproducible locally even with the tmux server cgroup-throttled to 15% CPU. Affected scripts fif_006/fif_015 now skip loudly on CI only (see their guard comments).

Root-cause area: hangon's tmux-backed key path (`sendKeysTmux` → `tmux send-keys <name>`) vs its legacy PTY/pipe fallback (`keyMap`, raw bytes written to a possibly-echoing tty which renders control chars as caret notation); hangon's non-atomic `~/.hangon/state.json` also races under load (separate, already-documented hazard below).

Upstream fix plan (`joewalnes/hangon`): 1) write `state.json` atomically (temp+rename under flock); 2) make `keys` delivery verify/avoid the cooked-tty echo path; 3) prefer `tmux send-keys -H <hex>` for special keys to bypass name lookup differences. Until fixed upstream, the runner's serial-retry guard plus the two CI skips keep CI signal clean.
