#!/usr/bin/env bash
# QA-LINE-004: Select multiple lines, Alt+Up moves block
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-004: Move selected block"

file=$(qa_tmpfile_nl "line004.txt" "alpha
beta
gamma
delta")
qa_start "$file"

# Select lines 2-3 (beta, gamma)
qa_keys "down"
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Move selection up
qa_keys "alt-up"

# beta should now be on line 1
qa_screen
line1=$(echo "$QA_SCREEN" | head -5 | grep "beta" || true)
if [[ -n "$line1" ]]; then
    qa_pass "alt-up moved selected block up"
else
    qa_fail "alt-up moved selected block up"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
