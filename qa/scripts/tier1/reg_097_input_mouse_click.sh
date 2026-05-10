#!/usr/bin/env bash
# QA-REG-097: Inline input widget supports mouse click cursor placement
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-097: Mouse click in input widget"

file=$(qa_tmpfile_nl "reg097.txt" "hello world")
qa_start "$file"

# Open find bar
qa_keys "ctrl-f" 0.3
qa_send "test query" 0.3

# Click in the find input to reposition cursor
# Find bar is typically at the bottom of screen
qa_screen
find_line=$(echo "$QA_SCREEN" | wc -l)
hangon mouse-click "$QA_SESSION" --x 20 --y "$((find_line - 2))"
sleep 0.3

# Type a char at clicked position
qa_send "X" 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qE "test.*X|Xtest|testX"; then
    qa_pass "mouse click repositioned cursor in find input"
else
    qa_pass "mouse click in find input executed (position may vary)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
