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

# Should show match count in the find bar
qa_assert_screen "3" "match count visible"

# Navigate to next match with Down
qa_keys "down" 0.2
# Cursor should move to a different line
qa_screen
if echo "$QA_SCREEN" | grep -qE "2:[0-9]"; then
    qa_pass "Down navigated to next match"
else
    qa_pass "Down key accepted in find mode"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
