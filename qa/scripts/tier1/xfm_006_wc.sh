#!/usr/bin/env bash
# QA-XFM-006: Select text, wc -l replaces with line count
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-006: Transform wc -l"

file=$(qa_tmpfile_nl "xfm006.txt" "line one
line two
line three")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
sleep 0.3

qa_keys "ctrl-a" 0.1
qa_send "wc -l" 0.2
qa_keys "enter"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "3|  *3"; then
    qa_pass "wc -l replaced text with line count"
else
    qa_fail "wc -l replaced text with line count"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
