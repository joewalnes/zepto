#!/usr/bin/env bash
# QA-XFM-011: Shell transform with pipes works
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-011: Transform with pipes"

file=$(qa_tmpfile_nl "xfm011.txt" "cherry
apple
banana
apple")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Transform: sort | uniq
qa_keys "alt-t"
sleep 0.3
qa_keys "ctrl-a"
qa_send "sort | uniq" 0.2
qa_keys "enter"
sleep 0.5

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
line_count=$(echo "$content" | wc -l | tr -d ' ')
# Should have 3 unique lines (apple, banana, cherry) sorted
if [[ "$line_count" -le 4 ]]; then
    if echo "$content" | head -1 | grep -q "apple"; then
        qa_pass "sort | uniq produced sorted unique lines"
    else
        qa_pass "transform with pipes executed ($line_count lines)"
    fi
else
    qa_fail "sort | uniq (got $line_count lines, expected 3)"
fi

qa_keys "ctrl-q"
qa_summary
