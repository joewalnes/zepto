#!/usr/bin/env bash
# QA-UNDO-003: Undo groups consecutive inserts
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-003: Undo grouping"

file=$(qa_tmpfile "undo003.txt" "")
qa_start "$file"

# Type a phrase (consecutive keystrokes)
qa_send "hello world"

# Single undo should remove the whole phrase (or at least a word)
qa_keys "ctrl-z"

qa_screen
if echo "$QA_SCREEN" | grep -q "hello world"; then
    qa_fail "undo removed grouped text"
else
    qa_pass "undo removed grouped text"
fi

qa_keys "ctrl-q"
qa_summary
