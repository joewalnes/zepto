#!/usr/bin/env bash
# QA-REG-057: Ctrl+S saves from find mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-057: Save from find mode"

file=$(qa_tmpfile_nl "reg057.txt" "content")
qa_start "$file"

# Modify
qa_keys "end"
qa_send " added"
sleep 0.2

# Open find bar
qa_keys "ctrl-f"
sleep 0.2

# Save from find mode
qa_keys "ctrl-s"
sleep 0.3

# Close find
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Verify saved
qa_assert_file_contains "$file" "added" "file saved from find mode"

qa_keys "ctrl-q"
qa_summary
