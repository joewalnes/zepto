# Asks

The user's own requests, tracked separately from machine-found work (`bugs.md`'s "Still open" list, `/scorecard` findings). Ranked highest-priority first. One agent must always be working the top open item here before dispatching anything from the general backlog — see `CLAUDE.md`'s "Agent operations" section.

Mark an item `[DONE — <date>, <commit/PR ref>]` in place when finished. Don't delete or renumber; this file is short-lived state, not an archive, but keep the ordering stable while items are open so cross-references don't break.

---

## 0. [DONE — 2026-09-01, branch `fix-cursor-out-of-bounds`] Cursor can end up outside valid line numbers after paste → undo → move/redo (2026-09-01)

**Highest priority — work this before anything else in this file, including the item below.** Reported live, exact repro not yet pinned down: *"I pasted a block of text, then hit undo, then some sequence of moving / redo, and my cursor ended up outside of the valid line numbers. I'm not sure exactly how I did it."* This is a P0-class report per this project's own bug severity scale (`bugs.md`: "P0: Data loss, crash, or fundamentally wrong behavior") — an out-of-range cursor position is exactly the kind of state that can crash on the next edit or silently corrupt the document, and it's in the undo/redo + cursor-position machinery that `Document.pm`'s undo-group fix (item 1, finding #3/#4 below) touched this very session.

Not yet reproduced. First step is systematic repro-hunting: paste a multi-line block, undo, then try various move/redo sequences (single redo, redo-then-move, move-then-redo, multiple undos before redo, undo/redo interleaved with arrow keys and Page Up/Down, undo/redo across a line that was deleted then the deletion undone) — probably needs a table of (cursor_line, cursor_col, doc_line_count) asserted in-range after every step of a `tests/*.t` fuzz-style sweep, not just one hand-picked sequence, since the user themselves couldn't pin down the exact trigger. Once reproduced: root-cause via Rule 5 (reproduce first, fix, verify), likely somewhere in `Document.pm`'s undo/redo cursor-restoration logic or `Editor.pm`'s cursor-clamping after an undo/redo event — check whether the `_content_version` fix (QA-REG-228, landed this session) or the undo-group changes touched cursor-position restoration at all, since the timing is suspicious even if unrelated.

## 1. Get every `/scorecard` category to B- or better (2026-09-01)

Full scorecard report: see `bugs.md`'s 2026-09-01 entries and the conversation where it was run. Current grades below B-:

| Category | Grade | What's needed |
|---|---|---|
| DRY | C+ | Pill-rendering helper (`_render_pill_list`) exists but isn't used at 4+ call sites in `Renderer.pm`; syntax-grammar duplication (large, architecturally "copy this template" by design — see note below) |
| Documentation | C+ | `qa/01_installation_and_cli.txt` / `qa/36_preferences.txt` hardcode `/Users/joe/src/zepto` — the exact mistake `CLAUDE.md` itself cites as a past lesson |

Categories at exactly B- (also worth pushing up, lower priority than the two above): Architecture, Performance, Test Coverage, Error Handling, Repo Hygiene.

**Concrete findings to fix, roughly in priority order (not all are DRY/Documentation — grouped here since they came from the same audit):**
1. [DONE — 2026-09-01, `c4611a3` on `main`] `Terminal.pm::copy_to_clipboard` (lines ~567-593) — no `alarm()` hang-guard, unlike `paste_from_clipboard` which has one for the identical failure shape. MEDIUM bug. Fixed with the same alarm-guard idiom (`CLIPBOARD_COPY_ALARM_SECS`); QA-REG-222.
2. [DONE — 2026-09-01, `22d39ea` on `main`] `qa/01_installation_and_cli.txt`, `qa/36_preferences.txt` — hardcoded `/Users/joe/src/zepto` paths in example commands. Mechanical fix — switched to repo-relative paths/`.`.
3. [DONE — 2026-09-01, `e59af09` on `main`] `Document.pm::replace()` (lines ~412-435) — bypasses `_undo_group` check that `insert`/`delete` respect. Latent bug (no current caller triggers it), but real. Fixed by routing through `_push_undo()`; QA-REG-227. Fixing this also surfaced and fixed a third bug: `_push_undo()`'s grouped branch never bumped `_content_version`, causing stale WrapMap/Renderer/Minimap cache for any edit inside any undo group (pre-existing, also affected move-line and column-paste) — QA-REG-228.
4. [DONE — 2026-09-01, `e59af09` on `main`] Replace-All undo granularity inconsistency (`Editor.pm` ~3167-3293) — 1 undo entry for >100 matches, N entries for ≤100 (compounds with #3 above). Fixed by wrapping the ≤100 sync path in `begin_undo_group()`/`end_undo_group()`; target is 1 entry, matching the >100 path. QA-REG-226.
5. [DONE — 2026-09-01, `a424abb` on `main`] No `$SIG{__WARN__}` handler anywhere (only `$SIG{__DIE__}`) — `warn()` calls corrupt the TUI mid-session. Known open bug in `bugs.md`; this audit found a second live trigger at `Highlighter.pm:492`. Fixed with a process-wide handler (`Terminal.pm::install_warn_handler`/`restore_warn_handler`, installed/restored in `Editor::init`/`cleanup`) redirecting warnings to `warnings.log` under the state dir instead of the live screen. QA-REG-225. Underlying `warn()`-triggering causes (the regex-brace warning, the grammar-load-failure warning) intentionally left untouched — the fix is a generic safety net, not a per-trigger patch.
6. `FileTree.pm::_dir_vcs_status_from_hash` (~801-819) — O(D×S) VCS status scan, debounced but not fixed. Not yet picked up by the fleet.
7. [PARTIALLY DONE — 2026-09-01, `1d5c2ac` on `main`] `Renderer.pm` pill-rendering duplication — 4+ call sites hand-roll what `_render_pill_list` already does (tree-context pills ~4402-4418, Open File pill ~4444-4460, palette trigger pills ~4463-4480 and ~4785-4792). Investigated all 4: only the tree-context hint pills were genuinely duplicative (converted, `_render_pill_list` extended to support a non-interactive/no-hover mode). The other 3 (Open File pill, both palette trigger pills) have real behavioral differences — wider cap-inclusive click regions, no hover support, and a trailing-gap convention that avoids re-overflowing `$cols` (QA-REG-186) — converting them would be a genuine behavior change, not a no-op refactor, so left as-is. See `bugs.md`'s "PARTIALLY FIXED" entry for the full per-site breakdown.
8. `WrapMap.pm` calling public `Zepto::Renderer::*` functions directly, contradicting `DESIGN.md:88`'s claim that they're "private, underscore-prefixed" — they aren't. Fix the doc claim at minimum; consider whether the coupling itself should be addressed (architectural call, flag if unsure). Not yet picked up by the fleet.
9. [DECIDED — 2026-09-01, leave as-is, do not implement] Syntax-grammar duplication (comment/string-scanning blocks copied across ~15+ `Syntax/*.pm` files) — `Base.pm` explicitly says "copy this template," so this is *by design*. **User's call:** "leave. easier to reason with a grammar at [a] time than having to figure out what's shared." Closed — do not revisit without a new explicit ask. DRY grade stays capped by this; accepted tradeoff, not an oversight.

**Explicitly NOT part of this ask** (already fine, don't touch): Security (A-). The modifier-label redesign and scroll-EOF fix were the user's own prior work, verified and committed+pushed directly (not through the fleet) — already landed on `main`, nothing pending here.

## 2. Sticky/goal column for cursor movement (2026-09-01)

**Decided — ready to implement, no further sign-off needed on the design itself.** Reported live: "As I move cursor down across lines (either via mouse drag or arrows), the column indicator on top ruler jumps around due to lines ending before cursor position."

Design, confirmed by the user 2026-09-01:
- Track a separate "goal column" that survives moving through shorter lines (standard "sticky column" pattern).
- Show the cursor pinned at true end-of-line when goal > line length, rather than drawing past the text.
- End key sets goal = actual line end.
- Typing past-end: **snap to true end-of-line** (user's explicit decision — "snap to true end of line on type") — do not implement whitespace-padding, that option is rejected.

Still ship a screenshot for confirmation before merging (same as the modifier-label redesign) since this changes visible cursor/ruler behavior — but the underlying design itself does not need re-confirmation, only the final look.

## 3. Unify tab-bar and status-bar button/pill styling (2026-09-01)

Reported live: "buttons at bottom have pill shape, but at top (e.g. close, quit) use a different style. Also they're lowercase. Build a common component (reusable code)."

Needs investigation first: locate the tab-bar hint rendering code in `Renderer.pm` and compare against `_render_pill_list`/the status-bar pill helpers. Decide (or flag as DECISION NEEDED if it's not obvious) whether to point the tab-bar hints at the existing pill helper directly, or whether a new shared primitive is needed because the tab bar has different constraints (e.g. no click targets, different color needs). This is mechanical enough that a straightforward "point tab-bar hints at the existing helper" fix probably doesn't need a UX sign-off — but changing the tab bar's visual appearance is user-facing, so ship a screenshot for confirmation before merging, same as the modifier-label redesign did.

## 4. [DONE — 2026-09-01, logged not fixed] hangon resize mechanism after the tool's tmux-removal rewrite

**Resolved (for this project's purposes) by logging it as a hangon bug rather than working around it here.** `hangon`'s `2026-09-01 05:05` dev build dropped the `tmux resize-window -t hangon-<PID>` mechanism that `qa/lib/qa-helpers.sh`'s `qa_resize_window` (used by 11 QA scripts) and `CLAUDE.md`'s documented technique both depend on. Logged as a P1 bug in `../hangon/TODO.md` ("No way to resize a running session's terminal since the tmux-per-session rewrite") — that's upstream's problem to fix, not zepto's to work around. Until hangon ships a resize mechanism, the 11 resize-dependent QA scripts (see `bugs.md`'s "Repo hygiene" entry, 2026-09-01, for the list) may be unreliable in a fresh `hangon` environment — the fleet should note this as a known environmental gap when a resize-dependent script fails, not chase it as a zepto code bug or try to patch around hangon internally.
