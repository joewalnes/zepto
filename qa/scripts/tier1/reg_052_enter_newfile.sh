#!/usr/bin/env bash
# QA-REG-052: Enter on empty last line puts cursor on next line (P0)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-052: Enter on empty last line (P0 regression)"

file=$(qa_tmpfile "reg052.txt" "")
qa_start "$file"

# Type text
qa_send "abc"
qa_assert_screen "abc" "text typed"

# Press Enter
qa_keys "enter"

# Cursor should be on line 2, col 1
qa_assert_cursor_at "2:1" "cursor at line 2 col 1 after Enter"

# Type on new line
qa_send "xyz"
qa_assert_screen "xyz" "text typed on new line"
qa_assert_cursor_at "2:4" "cursor at line 2 col 4"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
