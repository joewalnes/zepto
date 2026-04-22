#!/usr/bin/env bash
# QA-PRMT-001: Save prompt Y/N/C behavior
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-001: Save prompt behavior"

file=$(qa_tmpfile_nl "prmt001.txt" "original")
qa_start "$file"
qa_send "edit"

# Use ctrl-q to trigger save prompt
qa_keys "ctrl-q"
sleep 0.3
qa_assert_screen "Save|Discard|Cancel" "prompt shows options"

# Press C = cancel
qa_send "c" 0.3
qa_assert_screen "edit" "C cancels prompt, buffer stays"

# Quit again and discard with N
qa_keys "ctrl-q"
sleep 0.3
qa_send "n" 0.3

# File on disk should be unchanged
qa_assert_file_contains "$file" "original" "file unchanged after discard"

qa_summary
