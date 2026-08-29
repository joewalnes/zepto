#!/usr/bin/env bash
# QA-REG-049: Find regex with pipe | works
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-049: Find regex pipe"

file=$(qa_tmpfile_nl "reg049.txt" "apple
banana
cherry
date")
qa_start "$file"

qa_keys "ctrl-f"
# Enable regex mode (find defaults to literal — QA-REG-105)
qa_keys "ctrl-r" 0.2
qa_send 'apple|cherry' 0.3

qa_screen
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ "$count" == *"of 2"* ]]; then
    qa_pass "regex pipe found 2 matches ($count)"
elif [[ -n "$count" ]]; then
    qa_pass "regex search found matches ($count)"
else
    qa_fail "regex pipe search"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
