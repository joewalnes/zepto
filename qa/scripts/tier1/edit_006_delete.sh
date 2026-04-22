#!/usr/bin/env bash
# QA-EDIT-006: Delete key removes char at cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-006: Delete key"

file=$(qa_tmpfile "edit006.txt" "abcdef")
qa_start "$file"

# Move to col 3 (after 'ab')
qa_keys "right" 0.1
qa_keys "right" 0.1

# Delete twice (removes 'c' and 'd')
qa_keys "delete" 0.1
qa_keys "delete" 0.1

qa_assert_screen "abef" "delete removed chars at cursor"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
