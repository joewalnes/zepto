#!/usr/bin/env bash
# QA-REG-017: Transform via shell (Alt+T)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-017: Transform via shell"

file=$(qa_tmpfile_nl "reg017.txt" "cherry
apple
banana")
qa_start "$file"

# Select all text
qa_keys "ctrl-a"

# Open transform
qa_keys "alt-t"
qa_assert_screen "Shell|sort|command|pipe|Transform" "transform prompt visible"

# Type sort command and execute
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

# NOTE: "apple" is one of the original three input words and is visible on
# screen even before the sort runs — grepping for it alone is a tautology.
# Assert the actual reordering: apple before banana before cherry.
qa_screen
apple_line=$(echo "$QA_SCREEN" | grep -n "apple" | head -1 | cut -d: -f1 || true)
banana_line=$(echo "$QA_SCREEN" | grep -n "banana" | head -1 | cut -d: -f1 || true)
cherry_line=$(echo "$QA_SCREEN" | grep -n "cherry" | head -1 | cut -d: -f1 || true)

if [[ -n "$apple_line" && -n "$banana_line" && -n "$cherry_line" \
      && "$apple_line" -lt "$banana_line" && "$banana_line" -lt "$cherry_line" ]]; then
    qa_pass "sort result: lines reordered alphabetically"
else
    qa_fail "sort result: lines reordered alphabetically" \
        "apple=$apple_line banana=$banana_line cherry=$cherry_line"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
