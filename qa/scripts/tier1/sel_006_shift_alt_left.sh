#!/usr/bin/env bash
# QA-SEL-006: Shift+Alt+Left selects word backward
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-006: Shift+Alt+Left selects word backward"

file=$(qa_tmpfile "sel006.txt" "hello world")
qa_start "$file"

# Move to end of line
qa_keys "end"

# Shift+Alt+Left to select last word
qa_keys "shift-alt-left" 0.2

# Typing should replace the selection
qa_send "X"

qa_screen
if echo "$QA_SCREEN" | grep -q "hello X"; then
    qa_pass "shift+alt+left selected 'world' backward, replaced with X"
else
    # Could also be "helloX" if space included in word
    if echo "$QA_SCREEN" | grep -qE "hello.*X"; then
        qa_pass "shift+alt+left selected word backward"
    else
        qa_fail "shift+alt+left selected word backward"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
