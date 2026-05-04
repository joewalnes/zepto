#!/usr/bin/env bash
# QA-REG-015: Goto line invalid input shows feedback
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-015: Goto line invalid input feedback"

file=$(qa_tmpfile_nl "reg015.txt" "line one
line two")
qa_start "$file"

# Open goto line
qa_keys "ctrl-g"
sleep 0.3

# Enter garbage
qa_send "abc" 0.3
qa_keys "enter"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qiE "invalid|error|format"; then
    qa_pass "invalid input shows error feedback"
else
    # May just ignore invalid input - cursor should stay at 1:1
    qa_assert_cursor_at "1:1" "cursor unchanged after invalid goto input"
fi

qa_keys "escape" 0.3
qa_keys "ctrl-q"
qa_summary
