#!/usr/bin/env bash
# QA-XFM-004: Select lines, Alt+T, sort
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-004: Transform sort"

file=$(qa_tmpfile_nl "xfm004.txt" "cherry
apple
banana")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
sleep 0.3

qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
first_line=$(echo "$content" | head -1)
if [[ "$first_line" == "apple" ]]; then
    qa_pass "sort command sorted lines (first=apple)"
else
    qa_fail "sort command sorted lines (first=$first_line)"
fi

qa_keys "ctrl-q"
qa_summary
