#!/usr/bin/env bash
# QA-SEL-013: Triple-click selects entire line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-013: Triple-click selects line"

file=$(qa_tmpfile_nl "sel013.txt" "first line
second line
third line")
qa_start "$file"

# Triple-click on "second line" (row 4 for tab bar + ruler + line 2)
hangon mouse-click "$QA_SESSION" --x 5 --y 4 --count 3
sleep 0.3

# Type to replace entire line
qa_send "REPLACED"

qa_assert_screen "first line" "first line intact"
qa_assert_screen "REPLACED" "second line replaced"
qa_assert_screen "third line" "third line intact"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
