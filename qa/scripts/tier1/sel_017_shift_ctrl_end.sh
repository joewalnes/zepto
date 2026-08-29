#!/usr/bin/env bash
# QA-SEL-017: Shift+Ctrl+End selects to end of document
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-017: Shift+Ctrl+End selects to end"

file=$(qa_tmpfile_nl "sel017.txt" "line one
line two
line three")
qa_start "$file"

# Cursor at 1:1, select to end with Shift+Ctrl+End
qa_raw $'\x1b[1;6F'

# Type to replace selection
qa_send "X"

# All content should be replaced
qa_assert_expect "X" "replacement visible"
qa_assert_not_screen "line one" "line one gone"
qa_assert_not_screen "line three" "line three gone"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
