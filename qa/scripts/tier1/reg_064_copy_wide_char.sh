#!/usr/bin/env bash
# QA-REG-064: Copy double-width chars doesn't crash (P0)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-064: Copy wide chars no crash (P0 regression)"

file=$(qa_tmpfile_nl "reg064.txt" "Hello 你好世界 emoji")
qa_start "$file"

qa_assert_expect "Hello" "file content visible"

# Select all and copy
qa_keys "ctrl-a"
qa_keys "ctrl-c"
sleep 0.3

# Editor should still be alive - no crash
if qa_alive; then
    qa_pass "editor alive after copying wide chars"
else
    qa_fail "editor alive after copying wide chars" "editor crashed"
fi

qa_keys "ctrl-q"
qa_summary
