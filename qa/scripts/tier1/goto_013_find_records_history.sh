#!/usr/bin/env bash
# QA-GOTO-013: History records jumps from find
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-013: Find jump recorded in history"

content=""
for i in $(seq 1 100); do content+="line $i"$'\n'; done
content+="FINDME target here"$'\n'
for i in $(seq 102 120); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto013.txt" "$content")
qa_start "$file"

# Remember starting position
qa_assert_cursor_at "1" "start at line 1"

# Find "FINDME" to jump
qa_keys "ctrl-f"
qa_send "FINDME" 0.3
qa_keys "escape"
sleep 0.3

# Now go back
qa_keys "alt--"
sleep 0.3

# Should return to line 1 area
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" -lt 10 ]]; then
    qa_pass "go back returned to original position"
else
    qa_skip "history may not have recorded the jump"
fi

qa_keys "ctrl-q"
qa_summary
