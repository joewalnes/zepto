#!/usr/bin/env bash
# QA-GOTO-015: Go Back/Forward in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-015: Go Back/Forward in palette"

file=$(qa_tmpfile_nl "goto015.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "go back" 0.3

qa_assert_screen "Go Back" "Go Back command found in palette"

qa_keys "escape"
sleep 0.2

qa_keys "ctrl-space"
qa_send "go forward" 0.3

qa_assert_screen "Go Forward" "Go Forward command found in palette"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
