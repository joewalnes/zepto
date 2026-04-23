#!/usr/bin/env bash
# QA-NAV-002: Alt+Right moves cursor by word
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-002: Word-right navigation"

file=$(qa_tmpfile "nav002.txt" "hello world foo")
qa_start "$file"

qa_assert_screen "1:1" "starts at 1:1"

qa_keys "alt-right" 0.2
qa_screen
# Should have moved past "hello"
if echo "$QA_SCREEN" | grep -qE "1:[4-9]"; then
    qa_pass "alt-right jumped past first word"
else
    qa_fail "alt-right jumped past first word"
fi

qa_keys "alt-right" 0.2
qa_screen
# Should have moved past "world"
if echo "$QA_SCREEN" | grep -qE "1:1[0-6]|1:[7-9]"; then
    qa_pass "alt-right jumped past second word"
else
    qa_fail "alt-right jumped past second word"
fi

qa_keys "ctrl-q"
qa_summary
