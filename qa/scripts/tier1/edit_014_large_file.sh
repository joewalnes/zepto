#!/usr/bin/env bash
# QA-EDIT-014: Large file opens and navigates
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-014: Large file handling"

# Create a 1K line file
content=""
for i in $(seq 1 1000); do content+="line $i with some content"$'\n'; done
file=$(qa_tmpfile_nl "edit014.txt" "$content")
qa_start "$file"
sleep 0.5

# Should open
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" == "1" ]]; then
    qa_pass "large file opened at line 1"
else
    qa_fail "large file opened at line 1 (at $QA_CURSOR_LINE)"
fi

# Jump to middle
qa_keys "ctrl-g"
qa_send "500" 0.2
qa_keys "enter"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 498 && "$QA_CURSOR_LINE" -le 502 ]]; then
    qa_pass "jumped to line 500 in large file (at $QA_CURSOR_LINE)"
else
    qa_fail "jumped to line 500 in large file (at $QA_CURSOR_LINE)"
fi

# Jump to end
qa_keys "ctrl-g"
qa_send "1000" 0.2
qa_keys "enter"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 998 ]]; then
    qa_pass "jumped to end of large file (at $QA_CURSOR_LINE)"
else
    qa_fail "jumped to end of large file (at $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
