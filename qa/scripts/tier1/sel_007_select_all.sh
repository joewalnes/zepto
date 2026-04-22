#!/usr/bin/env bash
# QA-SEL-007: Ctrl+A selects all
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-007: Ctrl+A selects all"

file=$(qa_tmpfile_nl "sel007.txt" "line one
line two
line three")
qa_start "$file"

qa_keys "ctrl-a"
qa_send "X"

# All content replaced with X
qa_assert_screen "X" "all text replaced"
qa_assert_not_screen "line one" "original line 1 gone"
qa_assert_not_screen "line three" "original line 3 gone"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
