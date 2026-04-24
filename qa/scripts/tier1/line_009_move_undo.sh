#!/usr/bin/env bash
# QA-LINE-009: Move line + undo reverts order
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-009: Move line undo"

file=$(qa_tmpfile_nl "line009.txt" "alpha
bravo
charlie")
qa_start "$file"

# Move line 1 (alpha) down — bravo should now be first
qa_keys "alt-down"
qa_screen
first_content=$(echo "$QA_SCREEN" | grep -E "alpha|bravo" | head -1)
if echo "$first_content" | grep -q "bravo"; then
    qa_pass "alt-down moved alpha below bravo"
else
    qa_fail "alt-down moved alpha below bravo"
fi

# Undo should restore original order — alpha first again
qa_keys "ctrl-z"
sleep 0.3

qa_screen
first_after_undo=$(echo "$QA_SCREEN" | grep -E "alpha|bravo" | head -1)
if echo "$first_after_undo" | grep -q "alpha"; then
    qa_pass "undo restored alpha to first position"
else
    qa_fail "undo restored alpha to first position"
fi

qa_keys "ctrl-q"
qa_summary
