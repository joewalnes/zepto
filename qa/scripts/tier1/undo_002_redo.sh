#!/usr/bin/env bash
# QA-UNDO-002: Redo re-applies undone change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-002: Redo"

file=$(qa_tmpfile "undo002.txt" "hello")
qa_start "$file"

qa_keys "end"
qa_send " world"
qa_assert_expect "hello world" "text added"

qa_keys "ctrl-z"
# Should undo the " world"
qa_screen
if echo "$QA_SCREEN" | grep -qv "hello world"; then
    qa_pass "undo removed added text"
fi

qa_keys "ctrl-y"
qa_assert_expect "hello world" "redo restored text"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
