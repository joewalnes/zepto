#!/usr/bin/env bash
# QA-GOTO-004: Go to :col (same line)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-004: Goto :col"

file=$(qa_tmpfile "goto004.txt" "abcdefghijklmnop")
qa_start "$file"

# Go to col 10 on current line
qa_keys "ctrl-g"
qa_send ":10" 0.2
qa_keys "enter"

qa_assert_expect "1:10" "cursor at col 10"

qa_keys "ctrl-q"
qa_summary
