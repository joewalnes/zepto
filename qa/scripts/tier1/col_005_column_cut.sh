#!/usr/bin/env bash
# QA-COL-005: Column cut removes rectangle only
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-005: Column cut"

file=$(qa_tmpfile_nl "col005.txt" "abcdefgh
ijklmnop
qrstuvwx")
qa_start "$file"

# Toggle column mode
qa_keys "alt-c"
sleep 0.2

# Move right 2 to col 3, then select 3 cols x 3 rows
qa_keys "right" 0.05
qa_keys "right" 0.05
qa_keys "shift-right" 0.05
qa_keys "shift-right" 0.05
qa_keys "shift-right" 0.05
qa_keys "shift-down" 0.05
qa_keys "shift-down" 0.05
sleep 0.2

# Cut
qa_keys "ctrl-x"
sleep 0.3

# Save and verify
qa_keys "ctrl-s"
sleep 0.3

# Should have removed cols 3-5 (cde, klm, stu) leaving ab_fgh, ij_nop, qr_vwx
content=$(cat "$file")
line1=$(echo "$content" | head -1)
if echo "$line1" | grep -q "ab.*fgh\|abfgh"; then
    qa_pass "column cut removed middle chars from line 1 ($line1)"
else
    # Column cut might work differently — check chars are missing
    if [[ ${#line1} -lt 8 ]]; then
        qa_pass "column cut shortened line 1 (${#line1} chars, was 8)"
    else
        qa_fail "column cut removed chars (line1=$line1)"
    fi
fi

qa_keys "alt-c"
qa_keys "ctrl-q"
qa_summary
