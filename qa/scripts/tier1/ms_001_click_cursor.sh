#!/usr/bin/env bash
# QA-MS-001: Click positions cursor in text
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-001: Click positions cursor"

file=$(qa_tmpfile_nl "ms001.txt" "hello world foo bar
second line here
third line of text
fourth line stuff
fifth line end")
qa_start "$file"

qa_assert_screen "1:1" "starts at 1:1"

# Click on line 3 (row 5 on screen: tab=1, ruler=2, lines start at 3)
# Gutter ~5 cols, so text starts at ~6. Click col 10 to be safe.
hangon mouse-click "$QA_SESSION" --x 10 --y 5
sleep 0.3

qa_assert_screen "3:" "cursor moved to line 3"

# Click back on line 1 (row 3), col 10 (in the text area)
hangon mouse-click "$QA_SESSION" --x 10 --y 3
sleep 0.3

qa_assert_screen "1:" "cursor back to line 1"

qa_keys "ctrl-q"
qa_summary
