#!/usr/bin/env bash
# QA-XFM-003: Shell transform to lowercase
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-003: Transform lowercase"

file=$(qa_tmpfile_nl "xfm003.txt" "HELLO WORLD")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Open transform (Alt+T)
qa_keys "alt-t"
sleep 0.3

qa_keys "ctrl-a"
qa_send "tr '[:upper:]' '[:lower:]'" 0.2
qa_keys "enter"
sleep 0.5

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
if echo "$content" | grep -q "hello world"; then
    qa_pass "shell transform to lowercase worked"
else
    qa_fail "shell transform to lowercase (got: ${content:0:40})"
fi

qa_keys "ctrl-q"
qa_summary
