#!/usr/bin/env bash
# QA-XFM-002: Shell transform to uppercase
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-002: Transform uppercase"

file=$(qa_tmpfile_nl "xfm002.txt" "hello world")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Open transform (Alt+T)
qa_keys "alt-t"
sleep 0.3

# Type shell command for uppercase
qa_keys "ctrl-a"
qa_send "tr '[:lower:]' '[:upper:]'" 0.2
qa_keys "enter"
sleep 0.5

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
if echo "$content" | grep -q "HELLO WORLD"; then
    qa_pass "shell transform to uppercase worked"
else
    qa_fail "shell transform to uppercase (got: ${content:0:40})"
fi

qa_keys "ctrl-q"
qa_summary
