#!/usr/bin/env bash
# QA-GOTO-006: Goto beyond EOF clamps to end
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-006: Goto beyond EOF"

file=$(qa_tmpfile_nl "goto006.txt" "line 1
line 2
line 3")
qa_start "$file"

qa_keys "ctrl-g"
qa_send "9999" 0.2
qa_keys "enter"

# Should be clamped to last line
qa_screen
if echo "$QA_SCREEN" | grep -qE "3:[0-9]"; then
    qa_pass "cursor clamped to last line"
else
    qa_fail "cursor clamped to last line"
fi

qa_keys "ctrl-q"
qa_summary
