#!/usr/bin/env bash
# QA-LINE-009: Move line + undo reverts order
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-009: Move line undo"

file=$(qa_tmpfile_nl "line009.txt" "alpha
bravo
charlie")
qa_start "$file"

# Move line 1 down
qa_keys "alt-down"
qa_assert_screen "bravo" "line moved"

# Undo should restore original order
qa_keys "ctrl-z"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "alpha"; then
    qa_pass "undo reverted move"
else
    qa_fail "undo reverted move"
fi

qa_keys "ctrl-q"
qa_summary
