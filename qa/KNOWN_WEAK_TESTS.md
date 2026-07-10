# Known weak QA tests

Tautological-test sweep from Phase 1 (test harness hardening). The anti-pattern
being hunted: a script types/creates text `X` as setup, performs the action
under test, then asserts `grep -q "X"` (or `qa_assert_screen "X"`) — which
passes whether or not the action under test actually worked, because `X` was
already guaranteed to be on screen before the action ran. See `qa/README.md`
"Don't write tautological tests" and `clip_001_copy_paste.sh`'s fix history
for the canonical example.

## Fixed in Phase 1

These were confirmed tautological and rewritten to assert on the actual
mutated state (what changed / what's left after the action), not on text
that was present regardless:

- `clip_001_copy_paste.sh` — paste assertion now checks the pasted
  *duplicate* ("worldhello" / 2x "hello"), not just "hello" (which was
  already on screen from setup typing).
- `clip_003_copy_line.sh` — copy-line-no-selection assertion now checks
  "first line" appears **twice** (duplicated by paste), not just once
  (which is true even with copy/paste completely broken).
- `clip_007_column_paste.sh`, `col_004_copy_paste_rect.sh` — column-paste
  assertions now check the actual mutated target line
  ("aaaadddd4444"/"abcd0000000000" in the saved file), not the unchanged
  original rows 1-3, which were on screen unconditionally. This rewrite
  uncovered and led to fixing a real product bug (QA-REG-101, bugs.md) —
  `_column_paste` silently pasted nothing when the pasted rows extended
  past the end of the document.
- `xfm_001_transform.sh`, `xfm_010_undo.sh`, `reg_017_transform.sh` — sort
  transform assertions now check actual alphabetical reordering
  (line-number comparison of apple/banana/cherry), not mere presence of
  "apple" — which is one of the three original input words and is visible
  on screen even *before* sort runs.

## Not yet fixed — candidates for a future pass

Found via the same heuristic sweep (grep for `qa_send "X"` followed later by
`grep -q "X"` / `qa_assert_screen "X"` in the same script) but not vetted or
fixed individually in Phase 1. **This list is a heuristic starting point, not
a verified defect list** — some are likely genuine tautologies, others may be
legitimate assertions where the sent text IS the feature under test (e.g.
"type X, assert X appears" is a real test of typing itself, not tautological
for that purpose) or where the marker text really can only appear via the
action under test (e.g. a unique search term that isn't in the visible
viewport until search jumps to it). Each one needs a human read of the
actual script to classify correctly before fixing.

Likely genuine offenders (setup text unrelated to the feature under test,
reappearing regardless of whether the feature worked):

- `ms_004_double_click.sh`, `ms_005_triple_click.sh`,
  `sel_013_select_line_tripleclick.sh` — "REPLACED" assertions after
  click-to-select-then-type; worth checking whether a failed selection
  would still produce text containing "REPLACED" somewhere (e.g. inserted
  without deleting the original selection).
- `undo_001_basic.sh`, `undo_002_redo.sh`, `undo_003_group.sh`,
  `undo_009_undo_across_save.sh` — undo/redo tests that re-check for
  typed text; verify the assertion is checking presence/absence at the
  *correct* point in the undo sequence, not just "text exists somewhere".
- `find_002_incremental.sh`, `find_013_ctrl_jk.sh`,
  `find_016_find_jump.sh` (reg_016) — search-then-assert-marker-visible
  patterns; check whether the marker is scrolled into view *only* by a
  working search jump, or whether it's already in the initial viewport.
- `pal_008_enter_exec.sh`, `pal_002_search.sh` — palette filter/exec
  assertions checking for typed filter text.
- `reg_055_save_as_track.sh` — already partly real (checks file-on-disk +
  content), but also has a screen-based re-check of the typed content that
  may be redundant/weak.

Lower-priority / likely fine as-is (marker text is plausibly only
producible by the feature under test, e.g. unique search strings that
wouldn't be in the initial viewport, or the sent text genuinely IS what's
being tested — typing, help doc content, etc.):

`cli_018_invalid_file.sh`, `clip_006_copy_unicode.sh`,
`clip_013_cut_copy_findbar.sh`, `col_012_palette_toggle.sh`,
`cplt_006_quote_skip.sh`, `cplt_009_dropdown.sh`, `cplt_010_tab_accepts.sh`,
`cplt_011_right_arrow.sh`, `cplt_012_esc_dismiss.sh`,
`cplt_020_paste_no_trigger.sh`, `edit_001_insert_ascii.sh`,
`edit_002_utf8.sh`, `edit_005_empty_file.sh`, `edit_009_autoindent.sh`,
`fif_003_navigate_result.sh`, `fif_005_regex.sh`, `fif_007_no_results.sh`,
`fif_008_backend.sh`, `fif_009_fallback_rg.sh`, `fif_010_fallback_perl.sh`,
`fif_012_click_result.sh`, `fif_015_esc_closes.sh`, `fif_017_no_match.sh`,
`file_010_new_file.sh`, `file_013_save_as_existing.sh`,
`find_001_open_bar.sh`, `find_003_jump_offscreen.sh`,
`find_014_esc_closes.sh`, `find_015_reopen.sh`, `find_023_special_chars.sh`,
`find_024_palette_replace.sh`, `help_002_about.sh`, `help_003_changelog.sh`,
`help_004_license.sh`, `help_005_shortcuts.sh`, `help_006_doc_section.sh`,
`help_007_offline.sh`, `line_008_dup_selection.sh`,
`mc_008_empty_buffer.sh`, `nf_004_palette.sh`, `pal_006_shortcut_filter.sh`,
`pick_003_fuzzy.sh`, `pick_005_untracked.sh`, `pick_006_gitignore.sh`,
`pick_010_long_path.sh`, `pref_011_palette_toggles.sh`,
`prmt_001_save_prompt.sh`, `rcn_007_cursor_aligned.sh`,
`rcn_009_fuzzy_filter.sh`, `rcn_010_tree_reveal.sh`,
`reg_004_save_atomic.sh`, `reg_009_shift_tab_fif.sh`, `reg_013_find_esc.sh`,
`reg_081_nerd_font_label.sh`, `reg_087_find_reopen.sh`,
`reg_089_right_ghost_char.sh`, `sel_015_type_replaces.sh`,
`thm_005_find_toggle.sh`, `thm_011_palette_name.sh`,
`undo_010_ghost_retrigger.sh`, `undo_011_after_reload.sh`.

## How to re-run the sweep

```sh
cd qa/scripts/tier1
for f in *.sh; do
  sent=$(grep -oE 'qa_(send|sendline) "[^"]+"' "$f" | sed -E 's/qa_(send|sendline) "//; s/"$//')
  [[ -z "$sent" ]] && continue
  while IFS= read -r s; do
    [[ -z "$s" || ${#s} -lt 4 ]] && continue
    grep -qF "$s" <<< "$(grep -E 'grep -q|qa_assert_screen' "$f")" && echo "$f :: '$s'"
  done <<< "$sent"
done
```
