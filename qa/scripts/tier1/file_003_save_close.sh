#!/usr/bin/env bash
# QA-FILE-003: Save and Close Tab via Ctrl+W
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-003: Save and Close Tab"

file1=$(qa_tmpfile_nl "file003_a.txt" "content A")
file2=$(qa_tmpfile_nl "file003_b.txt" "content B")
qa_start "$file1" "$file2"

# Modify first tab
qa_send " modified"
sleep 0.2

# Ctrl+W should save and close tab
qa_keys "ctrl-w"
sleep 0.5

# Should now be on tab 2
qa_assert_screen "content B" "switched to remaining tab"

# Check that first file was saved
qa_assert_file_contains "$file1" "modified" "file was saved before closing"

qa_keys "ctrl-q"
qa_summary
