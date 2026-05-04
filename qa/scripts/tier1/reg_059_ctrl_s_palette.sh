#!/usr/bin/env bash
# QA-REG-059: Ctrl+S saves from palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-059: Save from palette"

file=$(qa_tmpfile_nl "reg059.txt" "original")
qa_start "$file"

# Modify
qa_keys "end"
qa_send " modified"
sleep 0.2

# Open palette
qa_keys "ctrl-space"
sleep 0.2

# Save from palette
qa_keys "ctrl-s"
sleep 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_assert_file_contains "$file" "modified" "saved from palette mode"

qa_keys "ctrl-q"
qa_summary
