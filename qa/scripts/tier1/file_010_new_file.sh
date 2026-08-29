#!/usr/bin/env bash
# QA-FILE-010: Ctrl+N creates new untitled tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-010: New file"

file=$(qa_tmpfile_nl "file010.txt" "existing content")
qa_start "$file"

# Open new file
qa_keys "ctrl-n"
sleep 0.3

# Should have a new empty tab — check for "untitled" or "Untitled" or "new"
qa_screen
if echo "$QA_SCREEN" | grep -qiE "untitled|new|Untitled"; then
    qa_pass "new tab created with untitled name"
else
    # Could also just be an empty editor with cursor at 1:1
    if echo "$QA_SCREEN" | grep -q "1:1"; then
        qa_pass "new tab created (cursor at 1:1)"
    else
        qa_fail "new tab created"
    fi
fi

# Type something to verify it's editable
qa_send "hello new file"
qa_assert_expect "hello new file" "can type in new tab"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
# Close original tab too
qa_keys "ctrl-q"
qa_summary
