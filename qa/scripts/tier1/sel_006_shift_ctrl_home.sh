#!/usr/bin/env bash
# QA-SEL-006: Shift+Ctrl+Home selects to start of document
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-006: Shift+Ctrl+Home selection"

file=$(qa_tmpfile_nl "sel006.txt" "line one
line two
line three")
qa_start "$file"

# Go to end of file
qa_keys "ctrl-g"
qa_send "3" 0.2
qa_keys "enter"
qa_keys "end"

# Shift+Ctrl+Home = CSI 1;6H
qa_raw $'\x1b[1;6H' 0.3

# Type to replace entire selection
qa_send "X"

# Should have replaced all content with X
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
line_count=$(echo "$content" | wc -l | tr -d ' ')
if [[ "$line_count" -le 2 && "$content" == *"X"* ]]; then
    qa_pass "shift-ctrl-home selected to start and replaced"
else
    qa_fail "shift-ctrl-home selected to start (lines=$line_count)"
fi

qa_keys "ctrl-q"
qa_summary
