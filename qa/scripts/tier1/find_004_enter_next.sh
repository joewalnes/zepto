#!/usr/bin/env bash
# QA-FIND-004: Enter in find bar jumps to next match
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-004: Enter in find bar"

content=""
for i in $(seq 1 50); do content+="line $i content"$'\n'; done
content+="MARKER here"$'\n'
for i in $(seq 52 100); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "find004.txt" "$content")
qa_start "$file"

# Open find and search for MARKER
qa_keys "ctrl-f"
qa_send "MARKER"

# Should find it
qa_assert_expect "1 of 1" "found 1 match"

# Press Enter to jump to it and close find bar
qa_keys "enter" 0.3

# Should be near line 51 where MARKER is
qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 50 && "$QA_CURSOR_LINE" -le 52 ]]; then
    qa_pass "enter jumped to match at line $QA_CURSOR_LINE"
else
    qa_fail "enter jumped to match (at line $QA_CURSOR_LINE, expected ~51)"
fi

qa_keys "ctrl-q"
qa_summary
