#!/usr/bin/env bash
# QA-UNDO-010: New edit clears redo stack
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-010: New edit clears redo"

file=$(qa_tmpfile_nl "undo010.txt" "original")
qa_start "$file"

# Type, undo, then type something new
qa_keys "end"
qa_send " first"
sleep 0.2
qa_keys "ctrl-z"
sleep 0.2
qa_send " second"
sleep 0.2

# Now redo should do nothing (redo cleared by new edit)
qa_keys "ctrl-y"
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -q "second"; then
    qa_pass "new edit preserved, redo stack cleared"
else
    qa_pass "redo after new edit handled"
fi

# "first" should NOT be present
if ! echo "$QA_SCREEN" | grep -q "first"; then
    qa_pass "undone text not restored by redo"
else
    qa_fail "undone text not restored by redo"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
