#!/usr/bin/env bash
# QA-REG-061: Typing with selection replaces it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-061: Type replaces selection"

file=$(qa_tmpfile_nl "reg061.txt" "hello world")
qa_start "$file"

# Select "hello" (5 chars)
for i in $(seq 1 5); do qa_keys "shift-right" 0.05; done

# Type replacement
qa_send "X"

qa_assert_expect "X world" "typing replaced selection"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
