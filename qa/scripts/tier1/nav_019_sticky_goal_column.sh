#!/usr/bin/env bash
# QA-NAV-019: Sticky/goal column for vertical cursor movement
#
# ASKS.md item 2 (2026-09-01): "As I move cursor down across lines (either
# via mouse drag or arrows), the column indicator on top ruler jumps around
# due to lines ending before cursor position." Design: track a separate
# "goal" column that survives moving through shorter lines; pin the cursor
# at true end-of-line (never drawn past the text) when goal > line length;
# End sets goal = actual line end; typing while pinned past a short line's
# end snaps to the true end (no whitespace padding), then updates the goal.
#
# Discoverability: this is pure keyboard/mouse cursor-movement behavior,
# not a command — there is nothing to find in the palette because there is
# nothing to turn on. It should just feel like the expected, unsurprising
# way arrow keys/PageUp/PageDown already behave in every other editor.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-019: Sticky/goal column"

# Line 1 (46 chars) and line 4 (also long) sandwich two short lines, so a
# real-world "long line, arrow down through short lines, back to a long
# line" repro (the user's exact scenario) is directly testable.
content='This is a somewhat long line for column te
short
hi
This is another somewhat long line for testing'
file=$(qa_tmpfile_nl "nav019.pl" "$content")
qa_start "$file"

# --- Move to col 30 on line 1 (no word wrap by default for .pl files) ---
qa_keys "ctrl-g"
qa_send "1" 0.2
qa_keys "enter"
for i in $(seq 1 29); do qa_keys "right" 0.02; done
qa_assert_cursor_at "1:30" "Positioned at col 30 on line 1"

# --- Down through short lines: pinned at TRUE end, not drawn past text ---
qa_keys "down"
qa_assert_cursor_at "2:6" "Down to short line 2 (\"short\", 5 chars) - pinned at true end, not col 30"

qa_keys "down"
qa_assert_cursor_at "3:3" "Down to short line 3 (\"hi\", 2 chars) - pinned at true end"

# --- Down onto a longer line again: goal column (30) restored exactly ---
qa_keys "down"
qa_assert_cursor_at "4:30" "Goal column (30) restored on line 4 - this is the bug report's exact repro"

# --- Round trip back up ---
qa_keys "up"; qa_keys "up"; qa_keys "up"
qa_assert_cursor_at "1:30" "Goal column (30) still intact after a full round trip"

# --- Horizontal movement resets the goal ---
qa_keys "down"
qa_assert_cursor_at "2:6" "Pinned at end of short line again"
qa_keys "left"
qa_assert_cursor_at "2:5" "Left arrow moved off the pinned position"
qa_keys "down"
qa_assert_cursor_at "3:3" "Line 3 (\"hi\") - col 5 also clamps to true end here, so re-verify with a real move"
qa_keys "up"
qa_keys "up"
qa_assert_cursor_at "1:5" "Left-arrow reset the goal to 5 (not the original 30) - restored on line 1"

# --- Typing while pinned past a short line's end: snap to true end, no padding ---
qa_keys "ctrl-g"
qa_send "1" 0.2
qa_keys "enter"
for i in $(seq 1 29); do qa_keys "right" 0.02; done
qa_keys "down"
qa_assert_cursor_at "2:6" "Pinned at true end of \"short\" (goal 30 remembered internally)"
qa_send "Z"
qa_assert_cursor_at "2:7" "Typed char landed right after the true end (col 7), not padded out toward col 30"

qa_keys "ctrl-s"
sleep 0.3
line2=$(sed -n '2p' "$file")
if [[ "$line2" == "shortZ" ]]; then
    qa_pass "Saved file shows 'shortZ' - no whitespace padding was inserted before the typed char"
else
    qa_fail "Saved file line 2 should be 'shortZ' with no padding" "got: '$line2'"
fi

qa_keys "ctrl-q"
qa_summary
