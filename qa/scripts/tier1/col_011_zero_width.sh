#!/usr/bin/env bash
# QA-COL-011: Column selection zero-width on first activate
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-011: Zero-width column on activate"

file=$(qa_tmpfile_nl "col011.txt" "abcdef
ghijkl
mnopqr")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"
qa_assert_screen "COL" "COL indicator visible"

# No text should be highlighted yet (zero-width)
# Extend right to create actual selection
qa_keys "right" 0.1
qa_keys "right" 0.1

# Should still be in COL mode
qa_assert_screen "COL" "still in column mode after extending"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
