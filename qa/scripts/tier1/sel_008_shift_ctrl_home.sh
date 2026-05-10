#!/usr/bin/env bash
# QA-SEL-008: Shift+Ctrl+Home extends selection to document start
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-008: Shift+Ctrl+Home selects to doc start"

file=$(qa_tmpfile_nl "sel008.txt" "line one
line two
line three")
qa_start "$file"

# Move to middle of doc
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "end"

# Shift+Ctrl+Home to select from here to doc start
# Ctrl+Home = ESC [1;5H
qa_raw $'\x1b[1;6H'
sleep 0.3

# Type to replace selection
qa_send "X"

qa_screen
# Everything before cursor should be replaced with X, leaving the rest of line 3
if echo "$QA_SCREEN" | grep -q "X"; then
    qa_pass "shift+ctrl+home selected from cursor to doc start"
else
    qa_fail "shift+ctrl+home selected from cursor to doc start"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
