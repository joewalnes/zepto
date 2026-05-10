#!/usr/bin/env bash
# QA-NAV-007: Ctrl+End jumps to document end
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-007: Ctrl+End jumps to doc end"

content=""
for i in $(seq 1 50); do content+="line $i"$'\n'; done
file=$(qa_tmpfile "nav007.txt" "$content")
qa_start "$file"

qa_assert_screen "1:1" "starts at 1:1"

# Ctrl+End
qa_raw $'\x1b[1;5F'
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "5[0-1]:[0-9]"; then
    qa_pass "ctrl+end jumped to last line"
else
    qa_fail "ctrl+end jumped to last line"
fi

qa_keys "ctrl-q"
qa_summary
