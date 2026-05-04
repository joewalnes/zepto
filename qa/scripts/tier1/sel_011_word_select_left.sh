#!/usr/bin/env bash
# QA-SEL-011: Shift+Ctrl+Left selects word left
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-011: Shift+Ctrl+Left word select"

file=$(qa_tmpfile_nl "sel011.txt" "apple banana cherry")
qa_start "$file"

# Move to end
qa_keys "end"

# Shift+Ctrl+Left = CSI 1;6D
qa_raw $'\x1b[1;6D' 0.3

# Type to replace
qa_send "X"

# "cherry" should be replaced
qa_screen
if echo "$QA_SCREEN" | grep -q "banana X\|banana  X"; then
    qa_pass "shift-ctrl-left selected last word"
else
    if ! echo "$QA_SCREEN" | grep -q "cherry"; then
        qa_pass "shift-ctrl-left selected and replaced text"
    else
        qa_fail "shift-ctrl-left selected last word"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
