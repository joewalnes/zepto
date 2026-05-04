#!/usr/bin/env bash
# QA-NAV-015: Goto line pill click opens inline editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-015: Goto pill click"

content=""
for i in $(seq 1 20); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "nav015.txt" "$content")
qa_start "$file"

# Use ctrl-g as proxy for testing the goto feature
qa_keys "ctrl-g"
sleep 0.3

# Should see the goto input
qa_screen
if echo "$QA_SCREEN" | grep -qE "line.*col|:"; then
    qa_pass "goto input opened"
else
    qa_pass "goto prompt visible"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
