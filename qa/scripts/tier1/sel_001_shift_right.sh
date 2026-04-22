#!/usr/bin/env bash
# QA-SEL-001: Shift+Right extends selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-001: Shift+Right extends selection"

file=$(qa_tmpfile "sel001.txt" "abcdef")
qa_start "$file"

qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# 3 chars selected — typing should replace them
qa_send "X"

qa_assert_screen "Xdef" "shift+right selected 3 chars, typing replaced them"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
