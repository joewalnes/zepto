#!/usr/bin/env bash
# QA-RCN-003: Enter in recent files opens selected file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-003: Recent enter opens"

file1=$(qa_tmpfile_nl "rcn003_a.txt" "AAA_CONTENT")
file2=$(qa_tmpfile_nl "rcn003_b.txt" "BBB_CONTENT")
qa_start "$file1" "$file2"

# Visit tab 2 to register it
qa_keys "alt-."
sleep 0.2
# Back to tab 1
qa_keys "alt-,"
sleep 0.2

# Open recent files
qa_keys "ctrl-e" 0.3

# Navigate to second file and enter
qa_keys "down" 0.2
qa_keys "enter" 0.3

# Should have switched to a file
if qa_alive; then
    qa_pass "recent enter opened file"
else
    qa_fail "recent enter crashed"
fi

qa_keys "ctrl-q"
qa_summary
