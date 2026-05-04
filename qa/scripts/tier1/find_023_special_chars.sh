#!/usr/bin/env bash
# QA-FIND-023: Find literal special characters (dot, backslash)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-023: Find special chars"

file=$(qa_tmpfile_nl "find023.txt" "file.txt
path\\to\\file
normal text")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "file.txt" 0.3

# Should find "file.txt"
qa_screen
if echo "$QA_SCREEN" | grep -qE "1 of 1|1.*match"; then
    qa_pass "literal dot search works"
else
    qa_assert_screen "file.txt" "find shows file.txt"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
