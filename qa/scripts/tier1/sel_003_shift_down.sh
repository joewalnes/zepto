#!/usr/bin/env bash
# QA-SEL-003: Shift+Down extends multi-line selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-003: Shift+Down multi-line select"

file=$(qa_tmpfile_nl "sel003.txt" "line one
line two
line three")
qa_start "$file"

qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Two lines selected — typing replaces them
qa_send "X"

qa_assert_expect "X" "selection replaced"
qa_assert_not_screen "line one" "line one gone"
qa_assert_not_screen "line two" "line two gone"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
