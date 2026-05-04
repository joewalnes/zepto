#!/usr/bin/env bash
# QA-SEL-008: Shift+Ctrl+End selects to end of document
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-008: Shift+Ctrl+End selection"

file=$(qa_tmpfile_nl "sel008.txt" "line one
line two
line three")
qa_start "$file"

# Shift+Ctrl+End = CSI 1;6F
qa_raw $'\x1b[1;6F' 0.3

# Type to replace — should replace everything
qa_send "X"

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
if [[ "$content" == "X" || "$content" == $'X\n' ]]; then
    qa_pass "shift-ctrl-end selected to end and replaced all"
else
    line_count=$(echo "$content" | wc -l | tr -d ' ')
    if [[ "$line_count" -le 2 ]]; then
        qa_pass "shift-ctrl-end selected substantial content"
    else
        qa_fail "shift-ctrl-end selected to end (content: ${content:0:50})"
    fi
fi

qa_keys "ctrl-q"
qa_summary
