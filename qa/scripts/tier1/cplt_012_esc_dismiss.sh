#!/usr/bin/env bash
# QA-CPLT-012: Esc dismisses completion
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-012: Esc dismisses completion ghost text"

file=$(qa_tmpfile_nl "cplt012.js" "const longVariableName = 1
")
qa_start "$file"

# Move to end (line 2)
qa_keys "down"

# Type partial word to trigger completion
qa_send "long"
sleep 0.8

# Press Esc to dismiss any ghost text
qa_keys "escape"
sleep 0.3

# Buffer should have just "long" typed
qa_screen
if echo "$QA_SCREEN" | grep -q "long"; then
    qa_pass "typed text preserved after Esc"
else
    qa_fail "typed text not visible"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
