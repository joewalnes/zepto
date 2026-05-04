#!/usr/bin/env bash
# QA-MC-009: Duplicate Line Down via palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-009: Duplicate Line Down via palette"

file=$(qa_tmpfile_nl "mc009.txt" "only line here")
qa_start "$file"

# Use palette to duplicate line down
qa_keys "ctrl-space"
qa_send "duplicate down" 0.3
qa_keys "enter"
sleep 0.3

# Should now have two copies of the line
qa_screen
line_count=$(echo "$QA_SCREEN" | grep -c "only line here" || true)
if [[ "$line_count" -ge 2 ]]; then
    qa_pass "line duplicated down via palette"
else
    qa_fail "line not duplicated (count: $line_count)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
