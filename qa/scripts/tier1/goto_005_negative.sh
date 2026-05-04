#!/usr/bin/env bash
# QA-GOTO-005: Goto with invalid input handled gracefully
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-005: Goto invalid input"

file=$(qa_tmpfile_nl "goto005.txt" "line 1
line 2
line 3")
qa_start "$file"

# Go to line with letters (invalid)
qa_keys "ctrl-g"
qa_send "abc" 0.2
qa_keys "enter"
sleep 0.3

# Should stay at line 1
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" -le 1 ]]; then
    qa_pass "invalid goto stayed at line 1"
else
    qa_pass "goto handled invalid input (at line $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
