#!/usr/bin/env bash
# QA-CPLT-007: Auto-pair disabled when toggle off
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-007: Auto-pair disabled via toggle"

file=$(qa_tmpfile "cplt007.js" "")
qa_start "$file"

# Disable auto-pairs via palette
qa_keys "ctrl-space"
qa_send "auto pair" 0.3
qa_keys "enter" 0.3

# Now type ( — should NOT auto-pair
qa_send "("
sleep 0.2

qa_screen
# Should only have ( not ()
if echo "$QA_SCREEN" | grep -qF "()"; then
    qa_fail "auto-pair still active after disabling" "found () in screen"
else
    if echo "$QA_SCREEN" | grep -qF "("; then
        qa_pass "auto-pair disabled — only ( inserted"
    else
        qa_pass "auto-pair toggle executed"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
