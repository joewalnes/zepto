#!/usr/bin/env bash
# QA-REG-204: multi-cursor backspace that deletes a MULTI-LINE selection
# at one cursor no longer leaves a not-yet-processed cursor below the
# deleted range pointing at a line number that has ceased to exist
# (bugs.md P1 "...and multi-line-selection deletes — real data
# corruption").
#
# Repro shape: a secondary cursor is created via Ctrl+D on the last line
# of the file. The primary cursor then gets a fresh, genuine multi-line
# selection via click + shift-click (this does NOT clear the secondary
# cursor — only arrow-key navigation and Escape do). Backspacing deletes
# that multi-line selection, collapsing several lines into one. The bug:
# the old code only computed a column-shift ("delta") for SAME-line
# deletions; for a multi-line deletion it left delta at 0 and skipped
# fixing up other cursors entirely, so the secondary cursor kept whatever
# line number it had before — a line number the multi-line delete had
# just removed. The cursor-position readout in the status bar exposes
# this directly: pre-fix it reports a line that doesn't exist in the
# resulting (shorter) document.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-204: multi-cursor backspace with a multi-line selection keeps the other cursor's line correct"

# 4 lines: rows 0-2 will be swallowed by the primary's multi-line
# selection; "ab.ab" (line 3, containing two separate "ab" matches
# separated by ".") is where the secondary cursor lives, below the
# range that gets deleted.
file=$(qa_tmpfile_nl "reg204.txt" "row0
row1
row2
ab.ab")
qa_start "$file"
qa_assert_expect "ab\.ab" "file loaded"

# Terminal coordinates: header (tab bar) is row 1, ruler is row 2, so
# document line N (0-indexed) renders at terminal row N+3. This file's
# line numbers are all single digits, so the gutter is a constant width
# and document column N (0-indexed) renders at terminal column N+8
# (calibrated interactively: clicking term col 8 on a content row lands
# the cursor at doc col 0).
doc_row() { echo $(( $1 + 3 )); }
doc_col() { echo $(( $1 + 8 )); }

# Cursor to line 3 col 0 (on the first "ab" of "ab.ab") and create a
# second cursor via Ctrl+D on the other "ab" match.
hangon mouse-click "$QA_SESSION" --x "$(doc_col 0)" --y "$(doc_row 3)"
sleep 0.3
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_assert_screen "2 cursors" "Ctrl+D twice created two cursors on line 3"

# Give the primary cursor a fresh multi-line selection spanning lines
# 0-2 (click sets cursor + clears its OWN selection but does not touch
# the secondary cursor; shift-click extends from there).
hangon mouse-click "$QA_SESSION" --x "$(doc_col 0)" --y "$(doc_row 0)"
sleep 0.3
hangon mouse-click "$QA_SESSION" --x "$(doc_col 4)" --y "$(doc_row 2)" --shift
sleep 0.3
qa_assert_screen "2 cursors" "Secondary cursor survived the click + shift-click"
qa_assert_cursor_at "3:5" "Primary cursor's multi-line selection extends to end of row2"

# Backspace deletes the multi-line selection (rows 0-2 collapse away)
# AND the secondary cursor's own selected "ab" — in the same keypress.
qa_keys "backspace"
qa_assert_expect "\.ab" "Multi-line selection deleted; only \".ab\" remains on the surviving line"
qa_assert_not_screen "row[012]" "All three \"rowN\" lines were removed by the multi-line delete"
qa_assert_cursor_at "2:1" "Bystander cursor correctly reports line 2 (not a line number the deletion just removed)"

qa_keys "ctrl-q"
qa_summary
