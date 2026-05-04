#!/usr/bin/env bash
# QA-SEL-005: Shift+Home selects to beginning of line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-005: Shift+Home selection"

file=$(qa_tmpfile_nl "sel005.txt" "hello world here")
qa_start "$file"

# Move to end of line
qa_keys "end"

# Shift+Home to select to start
qa_keys "shift-home"
sleep 0.2

# Type to replace selection
qa_send "X"
qa_screen

# The whole line should have been replaced with just X
if echo "$QA_SCREEN" | grep -q "^X$\|  X "; then
    qa_pass "shift-home selected entire line content"
else
    # Check the line doesn't have the original content
    if ! echo "$QA_SCREEN" | grep -q "hello world here"; then
        qa_pass "shift-home selected and replaced line content"
    else
        qa_fail "shift-home selected line content"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
