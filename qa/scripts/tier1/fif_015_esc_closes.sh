#!/usr/bin/env bash
# QA-FIF-015: Esc closes find-in-files palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-015: Esc closes find-in-files"

file=$(qa_tmpfile_nl "fif015.txt" "hello world")
qa_start "$file"

# Open find-in-files
qa_keys "ctrl-f"
sleep 0.2
# Switch to find-in-files with ctrl-shift-f might not work; use palette approach
qa_keys "escape"
qa_keys "ctrl-space"
qa_send "find in files" 0.3
qa_keys "enter"
sleep 0.5

qa_send "hello" 0.3

# Press Esc to close
qa_keys "escape"
sleep 0.3

# Should be back to editor
qa_assert_screen "hello world" "editor visible after closing FIF"

qa_keys "ctrl-q"
qa_summary
