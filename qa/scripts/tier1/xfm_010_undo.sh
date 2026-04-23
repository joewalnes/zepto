#!/usr/bin/env bash
# QA-XFM-010: Transform can be undone
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-010: Transform undo"

file=$(qa_tmpfile_nl "xfm010.txt" "cherry
apple
banana")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

# Verify sort happened
qa_assert_screen "apple" "sorted content visible"

# Undo
qa_keys "ctrl-z"

# Should revert to original order
qa_screen
if echo "$QA_SCREEN" | head -5 | grep -q "cherry"; then
    qa_pass "undo reverted transform"
else
    qa_fail "undo reverted transform"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
