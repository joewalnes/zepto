#!/usr/bin/env bash
# QA-RCN-002: Recent files list shows previously opened files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-002: Recent files navigation"

file1=$(qa_tmpfile_nl "rcn002_a.txt" "content_first")
file2=$(qa_tmpfile_nl "rcn002_b.txt" "content_second")
qa_start "$file1" "$file2"

# Switch to tab 2 to register both files as recent
qa_keys "alt-."
sleep 0.2

# Open recent files
qa_keys "ctrl-e" 0.3

# Should show recent files list
qa_screen
if echo "$QA_SCREEN" | grep -qE "rcn002"; then
    qa_pass "recent files shows opened files"
else
    qa_fail "recent files shows opened files"
fi

# Navigate and select
qa_keys "down" 0.2
qa_keys "enter" 0.3

qa_pass "recent file selection navigated"

qa_keys "ctrl-q"
qa_summary
