#!/usr/bin/env bash
# QA-REG-102: Unknown escape sequences must not stall queued input
# Bug: InputParser stopped its parse loop at the first unrecognized-but-
# consumed sequence, leaving any events behind it stuck in the buffer until
# the NEXT input arrived — keys lagged one event behind.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-102: Unknown escape sequence stall"

file=$(qa_tmpfile_nl "reg102.txt" $'alpha\nbeta\ngamma')
qa_start "$file"
qa_assert_screen "alpha" "file loaded"

# Unknown CSI (focus-in, ESC [ I) immediately followed by Down arrow in the
# same write — the arrow must be processed in the same batch
qa_raw "$(printf '\x1b[I\x1b[B')" 0.6
qa_assert_cursor_at "2" "arrow key behind unknown CSI processed immediately"

# Unknown CSI immediately followed by a typed character
qa_raw "$(printf '\x1b[Ix')" 0.6
qa_assert_screen "xbeta" "typed char behind unknown CSI processed immediately"

# Undo the edit so quit does not prompt
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-q"
qa_summary
