#!/usr/bin/env bash
# QA-EDIT-009: Enter creates new line with auto-indent
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-009: Enter auto-indents from previous line"

file=$(qa_tmpfile_nl "edit009.py" "def foo():
    pass")
qa_start "$file"

# Move to end of line 2 ("    pass")
qa_keys "down"
qa_keys "end"

# Press Enter — should auto-indent to match "    " (4 spaces)
qa_keys "enter"
qa_send "return 1"

# Line 3 should have indented "return 1"
qa_assert_screen "return 1" "return 1 appears"

# Check we're on line 3
qa_assert_screen "3:" "cursor on line 3"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2

qa_summary
