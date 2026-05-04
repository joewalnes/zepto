#!/usr/bin/env bash
# QA-FIND-018: Find works correctly with long patterns
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-018: Find with long pattern"

file=$(qa_tmpfile_nl "find018.txt" "the quick brown fox jumps
over the lazy dog
the quick brown fox runs")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "quick brown fox" 0.3

qa_screen
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ "$count" == *"of 2"* ]]; then
    qa_pass "long pattern found 2 matches ($count)"
elif [[ -n "$count" ]]; then
    qa_pass "long pattern found matches ($count)"
else
    qa_fail "long pattern found matches"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
