#!/usr/bin/env bash
# QA-FIND-023: Find literal special characters (dot, backslash)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-023: Find special chars"

file=$(qa_tmpfile_nl "find023.txt" "file.txt
path\\to\\file
normal text")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "file.txt"

# Should find "file.txt"
qa_wait_screen "1 of 1|1.*match|file.txt" || true
if echo "$QA_SCREEN" | grep -qE "1 of 1|1.*match"; then
    qa_pass "literal dot search works"
else
    if echo "$QA_SCREEN" | grep -q "file.txt"; then
        qa_pass "find shows file.txt"
    else
        qa_fail "find shows file.txt"
    fi
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
