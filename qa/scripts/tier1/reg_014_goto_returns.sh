#!/usr/bin/env bash
# QA-REG-014: Goto line actually moves cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-014: Goto line moves cursor"

content=""
for i in $(seq 1 50); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "reg014.txt" "$content")
qa_start "$file"

qa_keys "ctrl-g"
qa_send "25" 0.2
qa_keys "enter"
sleep 0.2

qa_cursor_pos
if [[ "$QA_CURSOR_LINE" -ge 24 && "$QA_CURSOR_LINE" -le 26 ]]; then
    qa_pass "goto moved to line 25 (at $QA_CURSOR_LINE)"
else
    qa_fail "goto moved to line 25 (at $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
