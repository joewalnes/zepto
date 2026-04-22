#!/usr/bin/env bash
# QA-GOTO-003: Go to line:col format
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-003: Goto line:col"

# Create a file with enough lines
content=""
for i in $(seq 1 20); do
    content+="line $i content here"$'\n'
done
file=$(qa_tmpfile_nl "goto003.txt" "$content")
qa_start "$file"

qa_keys "ctrl-g"
qa_send "5:3" 0.2
qa_keys "enter"

qa_assert_screen "5:3" "cursor at line 5 col 3"

qa_keys "ctrl-q"
qa_summary
