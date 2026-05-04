#!/usr/bin/env bash
# QA-NAV-007: Ctrl+End jumps to end of document
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-007: Ctrl+End"

content=""
for i in $(seq 1 50); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "nav007.txt" "$content")
qa_start "$file"

# Should start at line 1
qa_assert_cursor_at 1 "starts at line 1"

# Ctrl+End — jump to end
qa_raw $'\x1b[1;5F' 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 49 ]]; then
    qa_pass "ctrl-end jumped to end of document (line $QA_CURSOR_LINE)"
else
    qa_fail "ctrl-end jumped to end of document (at line $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
