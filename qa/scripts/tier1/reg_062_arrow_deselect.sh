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

qa_assert_expect "hello" "arrow deselected (hello preserved)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
