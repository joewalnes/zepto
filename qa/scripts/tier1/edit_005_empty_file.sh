#!/usr/bin/env bash
# QA-EDIT-005: Operations on empty file don't crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-005: Empty file operations"

file=$(qa_tmpfile "edit005.txt" "")
qa_start "$file"

# Should start at 1:1
qa_assert_expect "1:1" "cursor at 1:1 on empty file"

# Type in empty file
qa_send "hello"
qa_assert_expect "hello" "can type in empty file"

# Undo
qa_keys "ctrl-z"

# Should be back to empty
qa_wait_screen "^$|1:1" || true
qa_screen
if ! echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "undo removed text in empty file"
else
    qa_fail "undo removed text in empty file"
fi

qa_keys "ctrl-q"
qa_summary
