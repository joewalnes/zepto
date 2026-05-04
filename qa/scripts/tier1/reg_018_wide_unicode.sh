#!/usr/bin/env bash
# QA-REG-018: Wide Unicode chars don't break cursor positioning
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-018: Wide Unicode width"

file=$(qa_tmpfile_nl "reg018.txt" "hello 世界 world
test ⚠️ here")
qa_start "$file"

# Navigate past wide chars
qa_keys "end"
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -gt 10 ]]; then
    qa_pass "cursor at end of line with wide chars (col $QA_CURSOR_COL)"
else
    qa_fail "cursor positioning with wide chars (col $QA_CURSOR_COL)"
fi

# Type after wide chars
qa_send "X"
qa_assert_screen "X" "can type after wide chars"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
