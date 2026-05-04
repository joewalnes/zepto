#!/usr/bin/env bash
# QA-GOTO-008: Esc cancels goto without jumping
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-008: Goto Esc cancels without jump"

content=""
for i in $(seq 1 20); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto008.txt" "$content")
qa_start "$file"

qa_assert_cursor_at "1:1" "starts at 1:1"

# Open goto, type number, Esc to cancel
qa_keys "ctrl-g"
qa_send "15" 0.2
qa_keys "escape"
sleep 0.3

# Cursor should still be at line 1 (not jumped to 15)
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" -eq 1 ]]; then
    qa_pass "Esc cancelled goto, cursor at line 1"
else
    qa_fail "Esc cancelled goto, cursor at line 1" "at line $QA_CURSOR_LINE"
fi

qa_keys "ctrl-q"
qa_summary
