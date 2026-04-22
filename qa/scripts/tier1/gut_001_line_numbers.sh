#!/usr/bin/env bash
# QA-GUT-001: Gutter shows line numbers
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GUT-001: Line numbers in gutter"

content=""
for i in $(seq 1 20); do
    content+="line $i text"$'\n'
done
file=$(qa_tmpfile_nl "gut001.txt" "$content")
qa_start "$file"

# Should see line numbers in the gutter
qa_assert_screen " 1" "line number 1 visible"
qa_assert_screen "10" "line number 10 visible"

qa_keys "ctrl-q"
qa_summary
