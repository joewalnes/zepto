#!/usr/bin/env bash
# QA-MS-003: Click+drag creates selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-003: Drag to select"

file=$(qa_tmpfile_nl "ms003.txt" "hello world foo bar
second line here")
qa_start "$file"

# Drag from col 5 to col 15 on line 1 (row 3 on screen)
hangon mouse-drag "$QA_SESSION" --from 5,3 --to 15,3
sleep 0.3

# Type to replace selection
qa_send "X"

qa_assert_expect "X" "drag created selection that was replaced"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
