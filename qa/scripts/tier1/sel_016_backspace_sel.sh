#!/usr/bin/env bash
# QA-SEL-016: Backspace deletes selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-016: Backspace deletes selection"

file=$(qa_tmpfile "sel016.txt" "hello world")
qa_start "$file"

# Select "hello"
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

qa_keys "backspace"

qa_assert_screen " world" "backspace deleted selection"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
