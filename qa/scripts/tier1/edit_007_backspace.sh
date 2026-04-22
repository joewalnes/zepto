#!/usr/bin/env bash
# QA-EDIT-007: Backspace deletes char before cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-007: Backspace"

file=$(qa_tmpfile "edit007.txt" "abcdef")
qa_start "$file"

# Move to end
qa_keys "end"

# Backspace twice (removes 'f' and 'e')
qa_keys "backspace" 0.1
qa_keys "backspace" 0.1

qa_assert_screen "abcd" "backspace removed trailing chars"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
