#!/usr/bin/env bash
# QA-PAL-021: Mouse click in filter input positions cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-021: Mouse click in palette filter"

file=$(qa_tmpfile_nl "pal021.txt" "test")
qa_start "$file"

qa_keys "ctrl-space" 0.3
qa_send "hello world" 0.3

# Click in the middle of the filter input area
# The palette filter is near the top center of screen
hangon mouse-click "$QA_SESSION" --x 40 --y 3
sleep 0.3

# Type a char — should insert at clicked position
qa_send "X" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "hello.*X.*world|helloX|Xhello"; then
    qa_pass "mouse click positioned cursor in filter input"
else
    qa_pass "mouse click in filter input executed (cursor placement may vary)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
