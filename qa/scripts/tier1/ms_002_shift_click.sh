#!/usr/bin/env bash
# QA-MS-002: Shift+Click extends selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-002: Shift+Click extends selection"

file=$(qa_tmpfile_nl "ms002.txt" "hello world foo bar
second line here
third line of text")
qa_start "$file"

# Click to set cursor position
hangon mouse-click "$QA_SESSION" --x 5 --y 3
sleep 0.3

# Shift+Click further right to create selection
hangon mouse-click "$QA_SESSION" --x 20 --y 3 --shift
sleep 0.3

# Type to replace selection
qa_send "X"

# "hello" should be partially replaced
qa_assert_expect "X" "shift+click created selection that was replaced"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
