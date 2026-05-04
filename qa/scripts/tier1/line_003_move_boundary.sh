#!/usr/bin/env bash
# QA-LINE-003: Move line at boundary (first line up, last line down)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-003: Move line at boundary"

file=$(qa_tmpfile_nl "line003.txt" "first
last")
qa_start "$file"

# Try to move first line up — should do nothing
qa_keys "alt-up"
sleep 0.2

qa_keys "ctrl-s"
sleep 0.3

line1=$(head -1 "$file")
if [[ "$line1" == "first" ]]; then
    qa_pass "move up at top boundary is no-op"
else
    qa_fail "move up at top boundary is no-op (line1=$line1)"
fi

# Move to last line, try to move down
qa_keys "ctrl-g"
qa_send "2" 0.2
qa_keys "enter"
qa_keys "alt-down"
sleep 0.2

qa_keys "ctrl-s"
sleep 0.3

line2=$(tail -1 "$file" | tr -d '\n')
if [[ "$line2" == "last" ]]; then
    qa_pass "move down at bottom boundary is no-op"
else
    qa_fail "move down at bottom boundary is no-op (last=$line2)"
fi

qa_keys "ctrl-q"
qa_summary
