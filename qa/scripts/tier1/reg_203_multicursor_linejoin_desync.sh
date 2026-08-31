#!/usr/bin/env bash
# QA-REG-203: multi-cursor backspace across a line-join no longer corrupts
# the not-yet-processed secondary cursor's position (bugs.md P1
# "Multi-cursor backspace/insert desyncs secondary cursor positions
# across line-joins and multi-line-selection deletes — real data
# corruption").
#
# Repro shape: two cursors created via Ctrl+D (⌥/select-next-occurrence)
# both land on the same line. Typing then backspacing collapses that line
# to empty and, on the next backspace, joins it into the previous
# ("PREFIX") line. The bug: the cursor that does its OWN backspace-join
# updates correctly, but the OTHER (bystander) cursor on that same
# now-joined-away line only had its LINE adjusted, never its COLUMN — so
# it silently pointed at the wrong place in "PREFIX", and the very next
# keystroke corrupted the middle of an unrelated word instead of
# appending after it.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-203: multi-cursor backspace across line-join keeps both cursors correct"

# "ab" appears twice on line 2, separated by "." so Ctrl+D's word-select
# treats them as two separate matches (not one "ab.ab" word).
file=$(qa_tmpfile_nl "reg203.txt" "PREFIX
ab.ab")
qa_start "$file"
qa_assert_expect "PREFIX" "file loaded"

# Move to line 2, col 0 (on the first "ab") and select both occurrences.
qa_keys "down"
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_assert_screen "2 cursors" "Ctrl+D twice created two cursors on line 2"

# Replace both selections with 'Z', producing "Z.Z" — then backspace
# twice: first collapses "Z.Z" -> "." -> "" (no join yet, both cursors
# stay on line 2); the SECOND backspace is the one that joins the
# now-empty line 2 into "PREFIX".
qa_send "Z"
qa_assert_screen "Z\.Z" "Both occurrences replaced with Z"
qa_keys "backspace"
qa_keys "backspace"
qa_assert_expect "PREFIX" "Line 2 fully joined back into PREFIX (single line remains)"
qa_assert_not_screen "\.Z|Z\.Z" "No leftover second line content remains after the join"
qa_assert_cursor_at "1:7" "Cursor that performed the join lands correctly at end of PREFIX (col 7)"

# The moment of truth: type a character. If the bystander cursor's column
# was never fixed up (the bug), it inserts into the MIDDLE of PREFIX
# (e.g. "QPREFIX..." at the very start) instead of appending after it
# alongside the correctly-positioned cursor.
qa_send "Q"
qa_assert_expect "PREFIXQQ" "Both cursors correctly append at the end of PREFIX (no corruption)"
qa_assert_not_screen "QPREFIX" "Bug signature (stray char inserted at the START of PREFIX) is absent"

qa_keys "ctrl-q"
qa_summary
