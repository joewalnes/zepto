#!/usr/bin/env bash
# QA-EDIT-004: Enter splits line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-004: Enter splits line"

file=$(qa_tmpfile_nl "edit004.txt" "hello world")
qa_start "$file"

# Move to between hello and world (after 5 chars)
qa_keys "right" 0.05
qa_keys "right" 0.05
qa_keys "right" 0.05
qa_keys "right" 0.05
qa_keys "right" 0.05

# Press enter to split
qa_keys "enter"

# Should now be on line 2
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" == "2" ]]; then
    qa_pass "enter moved cursor to line 2"
else
    qa_fail "enter moved cursor to line 2 (at line $QA_CURSOR_LINE)"
fi

# Save and check file
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
line_count=$(echo "$content" | wc -l | tr -d ' ')
if [[ "$line_count" -ge 2 ]]; then
    qa_pass "file now has $line_count lines after enter"
else
    qa_fail "file now has $line_count lines (expected 2+)"
fi

qa_keys "ctrl-q"
qa_summary
