#!/usr/bin/env bash
# QA-XFM-005: Select with duplicates, sort | uniq
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-005: Transform sort | uniq"

file=$(qa_tmpfile_nl "xfm005.txt" "banana
apple
banana
cherry
apple")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
sleep 0.3

qa_keys "ctrl-a" 0.1
qa_send "sort | uniq" 0.2
qa_keys "enter"
sleep 0.5

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
line_count=$(echo "$content" | grep -c '.' || true)
if [[ "$line_count" -le 3 ]]; then
    qa_pass "sort | uniq deduped ($line_count unique lines)"
else
    qa_fail "sort | uniq deduped (got $line_count lines)"
fi

qa_keys "ctrl-q"
qa_summary
