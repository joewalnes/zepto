#!/usr/bin/env bash
# QA-EDIT-020: Auto-closing bracket pairs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-020: Bracket auto-close"

file=$(qa_tmpfile_nl "edit020.js" "")
qa_start "$file"

# Ensure auto-pairs is ON
qa_keys "ctrl-space"
qa_send "auto pair" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -q '\[off\]'; then
    qa_keys "enter" 0.3
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
else
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
fi
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
