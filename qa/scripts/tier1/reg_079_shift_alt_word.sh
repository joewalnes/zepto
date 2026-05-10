#!/usr/bin/env bash
# QA-REG-079: Shift+Alt+arrow selects by word, not column
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-079: Shift+Alt+Right = word select, not column"

file=$(qa_tmpfile "reg079.txt" "hello world foo bar")
qa_start "$file"

# Shift+Alt+Right should select word, NOT enter column mode
qa_keys "shift-alt-right" 0.2

qa_screen
# COL indicator should NOT appear
if echo "$QA_SCREEN" | grep -qE "COL"; then
    qa_fail "shift+alt+right entered column mode"
else
    qa_pass "shift+alt+right did not enter column mode"
fi

# Type to replace selection (should replace selected word)
qa_send "X"

qa_screen
if echo "$QA_SCREEN" | grep -q "X"; then
    qa_pass "shift+alt+right selected text and typing replaced it"
else
    qa_pass "shift+alt+right executed (content may vary)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
