#!/usr/bin/env bash
# QA-REG-101: Keyboard input still renders after mouse hover motion
# Bug: after any hover-motion event, the main loop skipped rendering for all
# subsequent keyboard input — typed text and cursor moves were applied to the
# document but invisible until the next click/scroll.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-101: Render after hover motion"

file=$(qa_tmpfile_nl "reg101.txt" $'alpha\nbeta\ngamma')
qa_start "$file"
qa_assert_screen "alpha" "file loaded"

# Hover motion over the text area (no click) — this armed the render-skip bug
qa_hover 20 4

# Type a character with NO intervening click — it must appear immediately.
# Use a non-word char: word chars arm the completion debounce, whose firing
# masked the missed render (chars appeared ~100ms late instead of never).
qa_send "!" 0.6
qa_assert_screen '!alpha' "typed char renders after hover motion without a click"

# Hover again, then move the cursor with the keyboard — the status bar
# cursor pill must reflect the move immediately
qa_hover 25 4
qa_keys "down" 0.6
qa_assert_cursor_at "2" "arrow key moves cursor (and renders) after hover motion"

# Undo the edit so quit does not prompt
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-q"
qa_summary
