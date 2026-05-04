#!/usr/bin/env bash
# QA-EDIT-020: Auto-closing bracket pairs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-020: Bracket auto-close"

file=$(qa_tmpfile_nl "edit020.js" "")
qa_start "$file"

# Auto-pairs is ON by default (each test gets fresh state dir)
sleep 0.3

# Type opening bracket — should auto-insert closing bracket
qa_send "("
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qF "()"; then
    qa_pass "( auto-closed with )"
else
    qa_fail "( auto-closed with )"
fi

# Type opening brace
qa_keys "end"
qa_keys "enter"
qa_send "{"
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qF "{}"; then
    qa_pass "{ auto-closed with }"
else
    qa_fail "{ auto-closed with }"
fi

# Type opening square bracket
qa_keys "end"
qa_keys "enter"
qa_send "["
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qF "[]"; then
    qa_pass "[ auto-closed with ]"
else
    qa_fail "[ auto-closed with ]"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
