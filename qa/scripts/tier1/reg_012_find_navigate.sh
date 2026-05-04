#!/usr/bin/env bash
# QA-REG-012: Find navigation updates match index
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-012: Find navigation index"

file=$(qa_tmpfile_nl "reg012.txt" "alpha word
beta word
gamma word")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "word" 0.3

qa_screen
first=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)

qa_keys "down" 0.2

qa_screen
second=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)

if [[ -n "$first" && -n "$second" && "$first" != "$second" ]]; then
    qa_pass "find navigation changed index ($first → $second)"
else
    qa_fail "find navigation changed index (first=$first second=$second)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
