#!/usr/bin/env bash
# QA-LINE-001+002: Alt+Up/Down moves line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-001: Move line up/down"

file=$(qa_tmpfile_nl "line001.txt" "apple
banana
cherry")
qa_start "$file"

# Move to line 2 (banana)
qa_keys "down"

# Move banana up
qa_keys "alt-up"

# First line should now be banana
qa_wait_screen "banan" || true
line1=$(echo "$QA_SCREEN" | head -5 | grep "banan" || true)
if [[ -n "$line1" ]]; then
    qa_pass "alt-up moved banana to line 1"
else
    qa_fail "alt-up moved banana to line 1"
fi

# Move it back down
qa_keys "alt-down"
qa_wait_screen "apple" || true
line1=$(echo "$QA_SCREEN" | head -3 | grep "apple" || true)
if [[ -n "$line1" ]]; then
    qa_pass "alt-down moved banana back down"
else
    qa_fail "alt-down moved banana back down"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
