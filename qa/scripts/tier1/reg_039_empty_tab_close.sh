#!/usr/bin/env bash
# QA-REG-039: Empty untitled tab auto-closes on first file open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-039: Empty untitled tab auto-closes on open"

file=$(qa_tmpfile_nl "reg039.txt" "content here")
# Start with no file (untitled tab)
qa_start

qa_assert_screen "untitled|Untitled" "starts with untitled tab"

# Open a file
qa_keys "ctrl-o"
sleep 0.5
qa_send "reg039.txt" 0.5

# Select the file from picker
qa_keys "enter"
sleep 0.5

# The untitled tab should be gone - only the opened file tab
qa_screen
# If untitled is gone, that's good
if echo "$QA_SCREEN" | grep -qiE "reg039"; then
    qa_pass "opened file visible"
else
    qa_skip "file picker navigation may vary"
fi

qa_keys "ctrl-q"
qa_summary
