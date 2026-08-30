#!/usr/bin/env bash
# QA-EDIT-023: Editor correctness sweep (deterministic, saved-bytes half)
#
# This is the hybrid design's deterministic tier1 half. Companion:
# qa/scripts/tier2/editor_correctness_visual_sweep.sh (the vision-judge
# half, which checks the LIVE unsaved screen for the same edit sequences).
#
# WHY a hybrid, and why THIS pattern specifically: this generalizes the
# real bug found and fixed in this repo (bugs.md, "Stale duplicated tail
# on the cursor's own line after typing into a large file", QA-REG-165) —
# a ghost-text completion candidate that was self-referential (it offered
# back text already sitting after the cursor) rendered a duplicate SUFFIX
# ON SCREEN ONLY, while the saved document was correct at every step of
# that investigation. A pure vision judge would be an expensive, imprecise
# way to catch this class of bug on every keystroke; a pure deterministic
# save-and-diff check structurally CANNOT catch it at all, because the
# document was never wrong — only the screen paint was. So:
#   (a) THIS script performs a battery of edits at exactly the trigger
#       points that class of bug needs (word-front insertion, word-end/
#       boundary insertion, mid-word insertion, multi-cursor edits,
#       undo/redo, paste) and after each one SAVES and diffs the actual
#       bytes on disk against the exact expected content — cheap, no LLM,
#       catches anything that corrupts real data.
#   (b) The tier2 companion runs the SAME edit sequences but instead
#       screenshots the LIVE unsaved state and asks a vision judge whether
#       the on-screen line matches what the edit should have produced —
#       the only kind of check that can catch a repeat of the QA-REG-165
#       bug's signature (screen wrong, document fine).
# QA-REG-165's own regression script (reg_165_ghost_completion_self_match_
# render.sh) is intentionally left as-is and not superseded by this one —
# it pins the EXACT original repro (line 2000 of a 5000-line file) with
# tight, bug-specific assertions; this script is deliberately broader and
# less pinned to that one root cause, so it can catch a *different* future
# bug in the same neighborhood that reg_165 wouldn't be shaped to notice.
#
# Every assertion here is an EXACT line match (`sed -n 'Np' file`
# compared with `==`, not `grep`) — per qa/README.md's "Writing Good Test
# Assertions", a substring/grep check here would be close to tautological
# (the substring being searched for is usually a subset of what a broken
# self-match duplication would ALSO contain).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-023: Editor correctness sweep (deterministic)"

# Compare line LINE_NO of FILE against EXPECTED exactly (not substring).
assert_line_exact() {
    local file="$1" line_no="$2" expected="$3" desc="$4"
    local actual
    actual=$(sed -n "${line_no}p" "$file")
    if [[ "$actual" == "$expected" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Expected line ${line_no}: '$expected' -- Got: '$actual'"
    fi
}

# --- 1. Typing at the FRONT of an existing word -------------------------
# The exact trigger shape of QA-REG-165: cursor lands right before a word,
# typing prepends to it. A self-match ghost-text bug would have painted
# (screen-only) a stale duplicate of the word's own tail; check the SAVED
# file is correct regardless (document was never the part that broke).
{
    file=$(qa_tmpfile_nl "ec_front.txt" "frontwordtail
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_send "PRE" 0.3
    sleep 0.5   # give any debounced completion trigger a chance to fire
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 "PREfrontwordtail" "word-front insertion saved correctly"
    qa_stop
}

# --- 2. Typing at the END/boundary of an existing word -------------------
{
    file=$(qa_tmpfile_nl "ec_end.txt" "endwordhead
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_keys "end" 0.1
    qa_send "POST" 0.3
    sleep 0.5
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 "endwordheadPOST" "word-end insertion saved correctly"
    qa_stop
}

# --- 3. MID-word insertion -------------------------------------------------
# Cursor lands inside a word, not at either edge. This is the case that
# most directly exercises "content exists both before AND after the
# cursor on the same word" -- the exact ambiguity a self-referential
# completion candidate can get confused by.
{
    file=$(qa_tmpfile_nl "ec_mid.txt" "abcdefghij
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    for _ in $(seq 1 4); do qa_keys "right" 0.05; done   # cursor after "abcd"
    qa_send "XYZ" 0.3
    sleep 0.5
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 "abcdXYZefghij" "mid-word insertion saved correctly"
    qa_stop
}

# --- 4. Multi-cursor edit --------------------------------------------------
# Ctrl+D three times selects all 3 occurrences of "foo" as simultaneous
# cursors (established behavior, see mc_004_type_all.sh); typing replaces
# all of them at once. Verify EVERY occurrence changed, on BOTH lines.
{
    file=$(qa_tmpfile_nl "ec_multi.txt" "foo bar foo
baz foo end")
    qa_start "$file"
    qa_keys "ctrl-d" 0.1
    qa_keys "ctrl-d" 0.1
    qa_keys "ctrl-d" 0.1
    qa_send "Q" 0.3
    sleep 0.3
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 "Q bar Q" "multi-cursor edit: line 1 all occurrences replaced"
    assert_line_exact "$file" 2 "baz Q end" "multi-cursor edit: line 2 occurrence replaced"
    qa_stop
}

# --- 5. Undo/redo sequence -------------------------------------------------
# Three separate typed groups (separated by a real pause each, so they
# land as distinct undo units per undo_003_group.sh's documented
# grouping behavior), then undo twice and redo once. Each intermediate
# state is exact and unambiguous regardless of the precise grouping
# boundary, since every group is delimited by a leading space.
{
    file=$(qa_tmpfile_nl "ec_undoredo.txt" "")
    qa_start "$file"
    qa_send " AAA" 1.0
    qa_send " BBB" 1.0
    qa_send " CCC" 1.0
    qa_keys "ctrl-z" 0.4   # undo CCC group
    qa_keys "ctrl-z" 0.4   # undo BBB group
    qa_keys "ctrl-y" 0.4   # redo BBB group
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 " AAA BBB" "undo/redo sequence left exact expected content"
    qa_stop
}

# --- 6. Paste ---------------------------------------------------------------
# Copy one whole line, jump to end of file, paste as a new last line.
# Verifies the pasted bytes exactly, and that nothing else in the
# document shifted or duplicated unexpectedly.
{
    file=$(qa_tmpfile_nl "ec_paste.txt" "PASTEME
keep2
keep3")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_keys "shift-end" 0.1
    qa_keys "ctrl-c" 0.2
    qa_raw $'\x1b[1;5F' 0.2   # Ctrl+End (CSI 1;5F) -- hangon has no ctrl-end key name
    qa_keys "enter" 0.1
    qa_keys "ctrl-v" 0.3
    sleep 0.3
    qa_keys "ctrl-s" 0.3
    assert_line_exact "$file" 1 "PASTEME" "paste: source line untouched"
    assert_line_exact "$file" 2 "keep2" "paste: middle line untouched"
    assert_line_exact "$file" 3 "keep3" "paste: line before paste target untouched"
    assert_line_exact "$file" 4 "PASTEME" "paste: pasted content exact, no duplication/corruption"
    qa_stop
}

qa_summary
