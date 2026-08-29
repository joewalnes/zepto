#!/usr/bin/env bash
# QA-PAL-008: Enter executes selected palette command
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-008: Palette execute command"

file=$(qa_tmpfile_nl "pal008.txt" "test content")
qa_start "$file"

# Open palette and search for "New File"
qa_keys "ctrl-space"
qa_send "new file" 0.3
qa_keys "enter"
sleep 0.3

# Should have created a new untitled tab
qa_assert_expect "untitled" "new file command executed"

qa_keys "ctrl-q"
qa_summary
