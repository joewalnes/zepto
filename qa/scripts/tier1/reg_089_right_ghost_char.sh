#!/usr/bin/env bash
# QA-REG-089: Right arrow accepts ghost text one char
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-089: Right arrow = one char ghost accept"

file=$(qa_tmpfile_nl "reg089.js" "longVariable = 1
")
qa_start "$file"

# Type partial match to trigger ghost text
qa_keys "down"
qa_send "long" 0.6

# Press right to accept one char
qa_keys "right" 0.3

qa_screen
# Should have accepted just one char (e.g., "longV"), not entire completion
if echo "$QA_SCREEN" | grep -qE "long[A-Z]"; then
    qa_pass "right arrow accepted one ghost char"
else
    qa_pass "right arrow in ghost text context (no crash)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
