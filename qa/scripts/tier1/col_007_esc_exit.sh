#!/usr/bin/env bash
# QA-COL-007: Esc exits column mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-007: Esc exits column mode"

file=$(qa_tmpfile_nl "col007.txt" "abcdef
ghijkl")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"
qa_assert_screen "COL" "COL indicator visible"

# Esc should exit column mode
qa_keys "escape"
sleep 0.3

qa_assert_not_screen "COL" "COL indicator gone after Esc"

qa_keys "ctrl-q"
qa_summary
