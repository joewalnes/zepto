#!/usr/bin/env bash
# QA-PRMT-004: Save prompt - choose save, file is saved then editor quits
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-004: Save prompt saves and quits"

file=$(qa_tmpfile_nl "prmt004.txt" "original")
qa_start "$file"

# Modify buffer
qa_send " modified"

# Quit to trigger save prompt
qa_keys "ctrl-q"
sleep 0.3

qa_assert_screen "Save|Discard|Cancel" "save prompt visible"

# Choose save (Y)
qa_send "y" 0.5

# Editor should exit
sleep 0.5
if ! qa_alive 2>/dev/null; then
    qa_pass "editor exited after save"
else
    qa_fail "editor exited after save"
    qa_keys "ctrl-q"
fi

# File should contain the modification
qa_assert_file_contains "$file" "modified" "file was saved with changes"

qa_summary
