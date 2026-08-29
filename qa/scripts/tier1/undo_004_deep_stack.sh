#!/usr/bin/env bash
# QA-UNDO-004: Deep undo stack (many operations)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-004: Deep undo stack"

file=$(qa_tmpfile_nl "undo004.txt" "")
qa_start "$file"

# Type 20 separate characters with pauses to create undo points
for i in $(seq 1 20); do
    qa_send "x" 0.15
done

qa_assert_expect "xxxxxxxxxxxxxxxxxxxx" "typed 20 x's"

# Undo many times
for i in $(seq 1 15); do
    qa_keys "ctrl-z" 0.1
done

qa_screen
# Should have fewer than 20 x's
x_count=$(echo "$QA_SCREEN" | tr -cd 'x' | wc -c | tr -d ' ')
if [[ "$x_count" -lt 20 ]]; then
    qa_pass "deep undo removed characters ($x_count remaining)"
else
    qa_fail "deep undo removed characters ($x_count remaining, expected fewer than 20)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
