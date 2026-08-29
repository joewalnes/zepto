#!/usr/bin/env bash
# QA-GOTO-001: Ctrl+G opens goto input
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-001: Goto line input opens"

file=$(qa_tmpfile_nl "goto001.txt" "line one
line two")
qa_start "$file"

qa_keys "ctrl-g"
qa_assert_expect "line.*col|:col|Go to|Go To" "goto input visible with hint"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
