#!/usr/bin/env bash
# QA-COL-004: Column copy then paste preserves rectangle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-004: Column copy/paste rectangle"

file=$(qa_tmpfile_nl "col004.txt" "abcdefghij
klmnopqrst
uvwxyz1234
0000000000")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"

# Select 3 rows x 4 cols (down 2, right 4)
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Copy
qa_keys "ctrl-c"

# Exit column mode
qa_keys "escape"

# Move to line 4, col 1
qa_keys "ctrl-g"
qa_send "4:1" 0.2
qa_keys "enter"

# Paste
qa_keys "ctrl-v"

# Line 4 should have the pasted column data
qa_assert_expect "abcd|klmn|uvwx" "column paste visible"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
