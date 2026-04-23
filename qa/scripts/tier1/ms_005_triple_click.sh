#!/usr/bin/env bash
# QA-MS-005: Triple-click selects line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-005: Triple-click selects line"

file=$(qa_tmpfile_nl "ms005.txt" "first line
second line
third line")
qa_start "$file"

# Triple-click on line 2 (row 4 on screen)
hangon mouse-click "$QA_SESSION" --x 10 --y 4 --count 3
sleep 0.3

# Type to replace entire line
qa_send "REPLACED"

qa_assert_not_screen "second line" "line replaced after triple-click"
qa_assert_screen "REPLACED" "replacement text visible"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
