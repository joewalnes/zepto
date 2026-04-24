#!/usr/bin/env bash
# QA-FIND-012: Down/Up navigate between matches in find bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-012: Navigate find matches"

file=$(qa_tmpfile_nl "find012.txt" "apple banana
cherry apple
date apple fig")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "apple" 0.3

# Should show match count
qa_assert_screen "3" "match count visible"

# Find bar shows "N of M" — check initial match index
qa_screen
initial_match=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1)

# Navigate to next match with Down
qa_keys "down" 0.2

qa_screen
next_match=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1)

if [[ -n "$initial_match" && -n "$next_match" && "$initial_match" != "$next_match" ]]; then
    qa_pass "Down navigated to next match ($initial_match → $next_match)"
else
    qa_fail "Down navigated to next match (before=$initial_match after=$next_match)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
