#!/usr/bin/env bash
# QA-CLIP-003: Copy with no selection copies entire line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-003: Copy line (no selection)"

file=$(qa_tmpfile_nl "clip003.txt" "first line
second line")
qa_start "$file"

# No selection — copy should grab entire line
qa_keys "ctrl-c"

# Move to end of file and paste
qa_keys "down" 0.1
qa_keys "end" 0.1
qa_keys "enter"
qa_keys "ctrl-v"

qa_assert_expect "first line" "pasted line contains first line content"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
