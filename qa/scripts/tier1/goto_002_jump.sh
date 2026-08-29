#!/usr/bin/env bash
# QA-GOTO-002: Go to line N
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-002: Ctrl+G go to line"

# Create a 20-line file
content=""
for i in $(seq 1 20); do
    content+="line number $i here
"
done
file=$(qa_tmpfile "goto002.txt" "$content")
qa_start "$file"

# Should start at line 1
qa_assert_expect "1:1|1,1" "starts at line 1"

# Open goto
qa_keys "ctrl-g"
sleep 0.3

# The input should be visible — type line number
# First select-all and replace (input may be pre-filled)
qa_keys "ctrl-a" 0.1
qa_send "10"
qa_keys "enter"

# Should now be at line 10
qa_assert_expect "10:" "cursor at line 10"
qa_assert_expect "line number 10" "line 10 content visible"

# Test line:col format
qa_keys "ctrl-g"
sleep 0.3
qa_keys "ctrl-a" 0.1
qa_send "15:5"
qa_keys "enter"

qa_assert_expect "15:" "cursor at line 15"

qa_keys "ctrl-q"

qa_summary
