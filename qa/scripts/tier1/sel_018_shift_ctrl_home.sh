#!/usr/bin/env bash
# QA-SEL-018: Shift+Ctrl+Home selects from bottom to start
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-018: Shift+Ctrl+Home selects to start"

file=$(qa_tmpfile_nl "sel018.txt" "line one
line two
line three")
qa_start "$file"

# Move to end of document (Ctrl+End = CSI 1;5F)
qa_raw $'\x1b[1;5F' 0.3

# Select to start with Shift+Ctrl+Home
qa_raw $'\x1b[1;6H'

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
