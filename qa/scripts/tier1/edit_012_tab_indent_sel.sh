#!/usr/bin/env bash
# QA-EDIT-012: Tab indents a selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-012: Tab indents selection"

file=$(qa_tmpfile_nl "edit012.txt" "alpha
bravo
charlie")
qa_start "$file"

# Select all lines
qa_keys "ctrl-a"

# Tab to indent
qa_keys "tab"

# All lines should have leading spaces
qa_screen
if echo "$QA_SCREEN" | grep -qE "    alpha|   alpha"; then
    qa_pass "selection indented with spaces"
else
    qa_fail "selection indented with spaces"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
