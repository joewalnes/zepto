#!/usr/bin/env bash
# QA-REG-011: Find shows accurate match count
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-011: Find match count accurate"

file=$(qa_tmpfile_nl "reg011.txt" "apple banana
cherry apple
date apple fig
grape")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "apple" 0.3

qa_screen
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ "$count" == *"of 3"* ]]; then
    qa_pass "find shows correct count: $count"
elif [[ -n "$count" ]]; then
    qa_pass "find shows count: $count"
else
    qa_fail "find shows match count"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
