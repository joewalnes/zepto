#!/usr/bin/env bash
# QA-EDIT-008: Backspace at line start joins lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-008: Backspace joins lines"

file=$(qa_tmpfile_nl "edit008.txt" "hello
world")
qa_start "$file"

# Move to start of line 2 (down from 1:1)
qa_keys "down" 0.1

# Backspace at col 1 of line 2 should join with line 1
qa_keys "backspace"

qa_assert_screen "helloworld" "lines joined"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
