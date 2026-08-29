#!/usr/bin/env bash
# QA-UNDO-006: New edit clears redo stack
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-006: Redo stack cleared by new edit"

file=$(qa_tmpfile "undo006.txt" "abc")
qa_start "$file"

qa_keys "end"
qa_send "d"
# Now "abcd"

qa_keys "ctrl-z"
# Now "abc" — redo would restore "d"

# Make a different edit instead
qa_send "X"
# Now "abcX"

# Redo should do nothing (stack cleared)
qa_keys "ctrl-y"
qa_assert_expect "abcX" "redo does nothing after new edit"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
