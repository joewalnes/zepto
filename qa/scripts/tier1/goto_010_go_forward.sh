#!/usr/bin/env bash
# QA-GOTO-010: Go Forward (Alt+=) after Go Back
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-010: Go Forward"

content=""
for i in $(seq 1 100); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto010.txt" "$content")
qa_start "$file"

# Jump to line 30
qa_keys "ctrl-g"
qa_send "30" 0.2
qa_keys "enter"

# Jump to line 70
qa_keys "ctrl-g"
qa_send "70" 0.2
qa_keys "enter"

# Jump to line 90
qa_keys "ctrl-g"
qa_send "90" 0.2
qa_keys "enter"

# Go back twice
qa_keys "alt--"
sleep 0.2
qa_keys "alt--"
sleep 0.2

# Should be near line 30
qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 28 && "$QA_CURSOR_LINE" -le 32 ]]; then
    qa_pass "two go-backs returned near line 30 ($QA_CURSOR_LINE)"
else
    qa_fail "two go-backs returned near line 30 (at $QA_CURSOR_LINE)"
fi

# Go forward once
qa_keys "alt-="
sleep 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 68 && "$QA_CURSOR_LINE" -le 72 ]]; then
    qa_pass "go forward returned near line 70 ($QA_CURSOR_LINE)"
else
    qa_fail "go forward returned near line 70 (at $QA_CURSOR_LINE)"
fi

# Go forward again
qa_keys "alt-="
sleep 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 88 && "$QA_CURSOR_LINE" -le 92 ]]; then
    qa_pass "second go forward returned near line 90 ($QA_CURSOR_LINE)"
else
    qa_fail "second go forward returned near line 90 (at $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
