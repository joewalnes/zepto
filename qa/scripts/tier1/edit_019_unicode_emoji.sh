#!/usr/bin/env bash
# QA-EDIT-019: Unicode emoji and wide characters
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-019: Unicode emoji"

file=$(qa_tmpfile_nl "edit019.txt" "")
qa_start "$file"

# Type text with emoji
qa_send "hello 🌍 world"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "text around emoji visible"
else
    qa_fail "text around emoji visible"
fi

# Check we can navigate past it
qa_keys "home"
for i in $(seq 1 8); do qa_keys "right" 0.05; done
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -ge 7 ]]; then
    qa_pass "cursor navigates past emoji (col $QA_CURSOR_COL)"
else
    qa_fail "cursor navigates past emoji (col $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
