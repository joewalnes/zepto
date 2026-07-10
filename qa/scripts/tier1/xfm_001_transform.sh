#!/usr/bin/env bash
# QA-XFM-001+002: Alt+T opens transform and pipes through shell
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-001: Transform via shell"

file=$(qa_tmpfile_nl "xfm001.txt" "cherry
apple
banana")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Open transform
qa_keys "alt-t"
qa_assert_screen "Shell|sort|command|pipe|Transform" "transform input visible"

# The Shell: prompt pre-fills with "sort" — clear and type fresh
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

# Text should be sorted. NOTE: "apple" is one of the original three input
# words and is visible on screen even BEFORE the sort runs — grepping for it
# alone (as this test used to) is a tautology that can't detect a broken
# transform. Assert the actual reordering instead: alphabetically, apple
# must now appear before banana, which must appear before cherry.
qa_screen
apple_line=$(echo "$QA_SCREEN" | grep -n "apple" | head -1 | cut -d: -f1 || true)
banana_line=$(echo "$QA_SCREEN" | grep -n "banana" | head -1 | cut -d: -f1 || true)
cherry_line=$(echo "$QA_SCREEN" | grep -n "cherry" | head -1 | cut -d: -f1 || true)

if [[ -n "$apple_line" && -n "$banana_line" && -n "$cherry_line" \
      && "$apple_line" -lt "$banana_line" && "$banana_line" -lt "$cherry_line" ]]; then
    qa_pass "sort command executed — lines reordered alphabetically"
else
    qa_fail "sort command executed — lines reordered alphabetically" \
        "apple=$apple_line banana=$banana_line cherry=$cherry_line"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
