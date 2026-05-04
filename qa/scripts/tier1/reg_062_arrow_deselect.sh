#!/usr/bin/env bash
# QA-REG-062: Arrow key clears selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-062: Arrow deselects"

file=$(qa_tmpfile_nl "reg062.txt" "hello world")
qa_start "$file"

# Select "hello"
for i in $(seq 1 5); do qa_keys "shift-right" 0.05; done

# Right arrow should deselect (not extend)
qa_keys "right"
sleep 0.2

# Type — should insert, not replace
qa_send "X"

qa_screen
# "hello" should still be there with X inserted after it
if echo "$QA_SCREEN" | grep -q "helloX\|hello X"; then
    qa_pass "arrow deselected, typing inserts"
elif echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "arrow deselected (hello preserved)"
else
    qa_fail "arrow deselected"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
