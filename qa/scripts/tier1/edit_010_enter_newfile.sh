#!/usr/bin/env bash
# QA-EDIT-010: Enter on empty last line puts cursor on next line (P0 REGRESSION)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-010: Enter on new file goes to next line (P0 regression)"

file=$(qa_tmpfile "edit010.txt" "")
qa_start "$file"

# Type some text on line 1
qa_send "abc"
qa_assert_expect "abc" "text typed"

# Press Enter — cursor should move to line 2
qa_keys "enter"

# Check cursor is on line 2, col 1
qa_assert_expect "2:1|2,1|2: 1" "cursor at line 2 col 1 after Enter"

# Type on new line to confirm position
qa_send "xyz"
qa_assert_expect "xyz" "text on second line"
qa_assert_expect "2:4|2,4|2: 4" "cursor at line 2 col 4"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2

qa_summary
