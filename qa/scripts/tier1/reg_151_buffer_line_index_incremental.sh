#!/usr/bin/env bash
# QA-REG-151: Buffer line index stays correct across incremental
# single-char edits AND newline-crossing edits on large files
# (Buffer::_ensure_line_index() incremental-update regression coverage)
#
# NOTE: content assertions for the line actively under the cursor are
# verified by SAVING and reading the file back from disk, not by
# grepping the raw on-screen render of that one row. See bugs.md P2
# "Stale duplicated tail on the cursor's own line after typing into a
# large file" (found 2026-08-30) -- a pre-existing (confirmed present
# before this session's Buffer.pm changes too), unrelated rendering
# artifact that can leave a stale duplicate tail on just the cursor's
# own row on screen, even though the underlying document content is
# always correct on save. Neighboring (non-edited) rows were never
# observed to be affected, so those are asserted directly on screen.
#
# Also note: line counts are compared as DELTAS from a baseline captured
# AFTER Zepto's own first save (not from the raw shell-constructed file)
# -- qa_tmpfile_nl's content already ends in a newline and the helper
# appends another, so the pre-open file has an extra trailing blank line
# that Zepto normalizes away on save. Comparing Zepto-saved-count to
# Zepto-saved-count sidesteps needing to know that exactly.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-151: Buffer line index correct after incremental edits (large file)"

content=""
for i in $(seq 1 4000); do content+="row${i}text"$'\n'; done
file=$(qa_tmpfile_nl "reg151.txt" "$content")

qa_start "$file"

# --- Sequence of single-char (non-newline) inserts at a fixed cursor
# position mid-file -- the fast path that now updates the line index
# incrementally instead of triggering a full rebuild. Typing several
# characters in a row is exactly this pattern. Goto-line leaves the
# cursor at column 1, so the inserted text lands as a prefix. ---
qa_keys "ctrl-g"
qa_send "2000" 0.2
qa_keys "enter"
sleep 0.3
qa_send "abcde" 0.3
qa_keys "ctrl-s"
sleep 0.3

if [[ "$(sed -n '2000p' "$file")" == "abcderow2000text" ]]; then
    qa_pass "sequential single-char inserts build up correctly (verified on disk)"
else
    qa_fail "sequential single-char inserts build up correctly (verified on disk)" "Got: $(sed -n '2000p' "$file")"
fi

# Baseline line count, captured via Zepto's OWN save (see note above on
# why this isn't compared against the raw pre-open file).
baseline_count=$(wc -l < "$file" | tr -d ' ')

# --- Backspace the inserted chars off immediately (cursor is right
# after "abcde", so backspace removes exactly what was just typed --
# same fast path in reverse) and confirm the line returns to its
# original content. ---
for i in 1 2 3 4 5; do qa_keys "backspace" 0.05; done
qa_keys "ctrl-s"
sleep 0.3

if [[ "$(sed -n '2000p' "$file")" == "row2000text" ]]; then
    qa_pass "sequential backspaces restore original line (verified on disk)"
else
    qa_fail "sequential backspaces restore original line (verified on disk)" "Got: $(sed -n '2000p' "$file")"
fi

new_count=$(wc -l < "$file" | tr -d ' ')
if [[ "$new_count" == "$baseline_count" ]]; then
    qa_pass "line count unaffected by non-newline inserts/deletes"
else
    qa_fail "line count unaffected by non-newline inserts/deletes" "baseline=$baseline_count now=$new_count"
fi

# --- Neighboring lines must be untouched by any of the above. Checked
# via fresh goto-line jumps (not up/down from an ambiguous column) so
# these are simple, reliable, non-edited-line screen reads. ---
qa_keys "ctrl-g"
qa_send "1999" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "row1999text" "line above unaffected by non-newline inserts/deletes"

qa_keys "ctrl-g"
qa_send "2001" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "row2001text" "line below unaffected by non-newline inserts/deletes"

# --- Insert a newline (Enter) mid-file: this is the documented "slow
# path" that falls back to a full line-index rebuild. Confirm the split
# is still correct -- line count increases by one and both halves read
# right on disk. ---
qa_keys "ctrl-g"
qa_send "2000" 0.2
qa_keys "enter"
sleep 0.3
qa_send "SPLIT" 0.2
qa_keys "left" 0.05
qa_keys "left" 0.05
qa_keys "left" 0.05
qa_keys "left" 0.05
qa_keys "left" 0.1
qa_keys "enter"
sleep 0.3
qa_keys "ctrl-s"
sleep 0.3

if [[ "$(sed -n '2000p' "$file")" == "" && "$(sed -n '2001p' "$file")" == "SPLITrow2000text" ]]; then
    qa_pass "newline split produced correct two lines (verified on disk)"
else
    qa_fail "newline split produced correct two lines (verified on disk)" \
        "line2000='$(sed -n '2000p' "$file")' line2001='$(sed -n '2001p' "$file")'"
fi

split_count=$(wc -l < "$file" | tr -d ' ')
if [[ "$split_count" == "$((baseline_count + 1))" ]]; then
    qa_pass "line count increased by one after newline insert"
else
    qa_fail "line count increased by one after newline insert" "baseline=$baseline_count now=$split_count"
fi

# --- Delete across a newline (merge two lines): also falls back to a
# full rebuild. Goto-line lands on the now-EMPTY line 2000 at column 1
# -- do NOT press "end" here: on an empty line, column 1 is already
# trivially both the start AND the end, and End on an already-at-end
# cursor is a "smart end" that jumps to the document end instead (the
# empty-line mirror of the "smart home" quirk noted in reg_150), which
# would silently delete/merge the wrong thing. Delete forward directly
# from column 1 to remove the line's own newline and merge it with the
# next line. ---
qa_keys "ctrl-g"
qa_send "2000" 0.2
qa_keys "enter"
sleep 0.3
qa_keys "delete"
sleep 0.3
qa_keys "ctrl-s"
sleep 0.3

if [[ "$(sed -n '2000p' "$file")" == "SPLITrow2000text" ]]; then
    qa_pass "newline delete merged lines correctly (verified on disk)"
else
    qa_fail "newline delete merged lines correctly (verified on disk)" "Got: $(sed -n '2000p' "$file")"
fi

merge_count=$(wc -l < "$file" | tr -d ' ')
if [[ "$merge_count" == "$baseline_count" ]]; then
    qa_pass "line count back to baseline after split+merge round trip"
else
    qa_fail "line count back to baseline after split+merge round trip" "baseline=$baseline_count now=$merge_count"
fi

# --- Final sanity: lines far from all of the above edits are untouched. ---
if [[ "$(sed -n '1p' "$file")" == "row1text" ]]; then
    qa_pass "saved file: first line untouched"
else
    qa_fail "saved file: first line untouched" "Got: $(sed -n '1p' "$file")"
fi

if [[ "$(sed -n '4000p' "$file")" == "row4000text" ]]; then
    qa_pass "saved file: last real line untouched"
else
    qa_fail "saved file: last real line untouched" "Got: $(sed -n '4000p' "$file")"
fi

qa_keys "ctrl-q"
qa_summary
