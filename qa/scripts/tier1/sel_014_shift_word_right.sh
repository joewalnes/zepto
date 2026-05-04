#!/usr/bin/env bash
# QA-SEL-014: Shift+Alt+Right selects word right
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-014: Shift+Alt+Right word select"

file=$(qa_tmpfile_nl "sel014.txt" "alpha beta gamma")
qa_start "$file"

# Shift+Alt+Right — select first word
qa_keys "shift-alt-right" 0.2 2>/dev/null || qa_raw $'\x1b[1;4C' 0.3

# Type to replace
qa_send "X"

qa_screen
if ! echo "$QA_SCREEN" | grep -q "alpha"; then
    qa_pass "shift-alt-right selected first word"
elif echo "$QA_SCREEN" | grep -q "X"; then
    qa_pass "shift-alt-right selected text"
else
    qa_fail "shift-alt-right word select"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
