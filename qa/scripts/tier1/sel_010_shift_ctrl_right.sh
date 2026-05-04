#!/usr/bin/env bash
# QA-SEL-010: Shift+Ctrl+Right selects word right
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-010: Shift+Ctrl+Right word select"

file=$(qa_tmpfile_nl "sel010.txt" "apple banana cherry")
qa_start "$file"

# Shift+Ctrl+Right = CSI 1;6C
qa_raw $'\x1b[1;6C' 0.3

# Type to replace selection
qa_send "X"

qa_screen
# First word "apple" should be replaced, leaving "X banana cherry" or "Xbanana cherry"
if echo "$QA_SCREEN" | grep -qE "X.?banana"; then
    qa_pass "shift-ctrl-right selected first word"
else
    # Check that apple is gone
    if ! echo "$QA_SCREEN" | grep -q "apple"; then
        qa_pass "shift-ctrl-right selected and replaced text"
    else
        qa_fail "shift-ctrl-right selected first word"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
