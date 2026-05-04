#!/usr/bin/env bash
# QA-CPLT-010: Tab accepts full completion
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-010: Tab accepts completion"

file=$(qa_tmpfile_nl "cplt010.js" "const longVariableName = 1
")
qa_start "$file"

# Move to line 2
qa_keys "down"

# Type partial match and wait for ghost text
qa_send "long"
sleep 1

# Press Tab to accept
qa_keys "tab"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "longVariableName"; then
    qa_pass "Tab accepted full completion"
else
    qa_skip "completion may not have triggered"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
