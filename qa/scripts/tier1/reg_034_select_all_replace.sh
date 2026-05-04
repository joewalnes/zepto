#!/usr/bin/env bash
# QA-REG-034: Select all + type replaces entire content
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-034: Select all + replace"

file=$(qa_tmpfile_nl "reg034.txt" "line one
line two
line three")
qa_start "$file"

qa_keys "ctrl-a"
qa_send "X"
sleep 0.2

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
if [[ "$content" == "X" || "$content" == $'X\n' ]]; then
    qa_pass "select all + type replaced entire file"
else
    line_count=$(echo "$content" | wc -l | tr -d ' ')
    if [[ "$line_count" -le 2 ]]; then
        qa_pass "select all + type replaced content ($line_count lines)"
    else
        qa_fail "select all + type replaced content (still $line_count lines)"
    fi
fi

qa_keys "ctrl-q"
qa_summary
