#!/usr/bin/env bash
# QA-MS-004: Double-click selects word
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-004: Double-click selects word"

file=$(qa_tmpfile_nl "ms004.txt" "hello world foo bar")
qa_start "$file"

# Double-click on "world" (gutter ~5 cols, "world" starts at col ~12)
hangon mouse-click "$QA_SESSION" --x 14 --y 3 --count 2
sleep 0.3

# Type to replace the selected word
qa_send "REPLACED"

qa_assert_screen "hello REPLACED foo" "double-click selected and replaced word"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
