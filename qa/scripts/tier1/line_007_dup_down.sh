#!/usr/bin/env bash
# QA-LINE-007: Duplicate line down
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-007: Duplicate line down"

file=$(qa_tmpfile_nl "line007.txt" "alpha
beta
gamma")
qa_start "$file"

# Cursor on line 1 (alpha)
# Duplicate down — should insert copy below
qa_keys "ctrl-space"
qa_send "duplicate down" 0.3
qa_keys "enter" 0.3

qa_screen
# Should now have two "alpha" lines
count=$(echo "$QA_SCREEN" | grep -c "alpha" || true)
if [[ "$count" -ge 2 ]]; then
    qa_pass "duplicate down created copy of line"
else
    qa_fail "duplicate down created copy of line (found $count occurrences)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
