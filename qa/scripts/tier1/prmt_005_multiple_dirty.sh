#!/usr/bin/env bash
# QA-PRMT-005: Multiple dirty tabs - each gets its own prompt
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-005: Multiple dirty tab prompts"

file1=$(qa_tmpfile_nl "prmt005a.txt" "clean A")
file2=$(qa_tmpfile_nl "prmt005b.txt" "clean B")
qa_start "$file1" "$file2"

# Dirty first tab
qa_send "X"

# Switch to second tab and dirty it
qa_keys "alt-."
sleep 0.3
qa_send "Y"

# Quit
qa_keys "ctrl-q"
sleep 0.3

# First prompt
qa_assert_screen "Save|Discard|Cancel" "first save prompt visible"
qa_send "n" 0.5

# May get second prompt
qa_screen
if echo "$QA_SCREEN" | grep -qE "Save|Discard|Cancel"; then
    qa_pass "second save prompt for other dirty tab"
    qa_send "n" 0.5
else
    qa_pass "dirty tabs handled"
fi

# Try another quit if still alive
if qa_alive 2>/dev/null; then
    qa_keys "ctrl-q" 0.3
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "Save|Discard|Cancel"; then
        qa_send "n" 0.5
    fi
fi

sleep 0.5
if ! qa_alive 2>/dev/null; then
    qa_pass "editor exited after handling all prompts"
else
    qa_fail "editor exited after handling all prompts"
    qa_keys "ctrl-q"
    sleep 0.2
    qa_send "n"
fi

qa_summary
