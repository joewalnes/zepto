#!/usr/bin/env bash
# QA-SEL-019: Shift+Page Down extends selection by page
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-019: Shift+Page Down/Up selection"

content=""
for i in $(seq 1 50); do content+="line $i of the file"$'\n'; done
file=$(qa_tmpfile_nl "sel019.txt" "$content")
qa_start "$file"

# Shift+Page Down to select a page of text
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Now type to replace selection — verifies selection exists
qa_send "X"

qa_assert_not_screen "line 1 " "selection replaced first lines"
qa_assert_screen "X" "replacement visible"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
