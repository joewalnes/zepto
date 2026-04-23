#!/usr/bin/env bash
# QA-SEL-009: Arrow key without Shift clears selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-009: Arrow clears selection"

file=$(qa_tmpfile "sel009.txt" "abcdef")
qa_start "$file"

# Select 3 chars
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# Right arrow should clear selection and move cursor
qa_keys "right" 0.1

# Typing should insert, not replace
qa_send "X"

qa_assert_screen "abcdXef" "arrow cleared selection, X inserted at cursor"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
