#!/usr/bin/env bash
# QA-UNDO-001: Basic undo restores previous state
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-001: Basic undo"

file=$(qa_tmpfile_nl "undo001.txt" "hello")
qa_start "$file"

# Type " world" at end of line
qa_keys "end"
qa_send " world"
qa_assert_screen "hello world" "text modified to 'hello world'"

# Undo
qa_keys "ctrl-z"
sleep 0.3
qa_keys "ctrl-z"
sleep 0.3

# After enough undos, should revert toward "hello"
qa_screen
if echo "$QA_SCREEN" | grep -q "hello world"; then
    # May need more undos depending on grouping
    qa_keys "ctrl-z"
    sleep 0.3
fi

qa_screen
if ! echo "$QA_SCREEN" | grep -q "hello world"; then
    qa_pass "undo removed the added text"
else
    qa_fail "undo did not revert text" "still shows 'hello world'"
fi

# Redo
qa_keys "ctrl-y"
sleep 0.3
qa_assert_screen "hello" "after redo, text is present"

qa_keys "ctrl-q"
sleep 0.2
qa_send "d" 0.2

qa_summary
