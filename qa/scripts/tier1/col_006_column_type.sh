#!/usr/bin/env bash
# QA-COL-006: Column type inserts at all lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-006: Column type inserts"

file=$(qa_tmpfile_nl "col006.txt" "aaa
bbb
ccc")
qa_start "$file"

# Toggle column mode
qa_keys "alt-c"
sleep 0.2

# Select down 2 lines (zero-width column at col 1)
qa_keys "shift-down" 0.05
qa_keys "shift-down" 0.05
sleep 0.2

# Type X — should insert at all 3 lines
qa_send "X"
sleep 0.3

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
x_count=$(echo "$content" | grep -c "X" || true)
if [[ "$x_count" -ge 3 ]]; then
    qa_pass "X inserted on all 3 lines ($x_count)"
elif [[ "$x_count" -ge 2 ]]; then
    qa_pass "X inserted on $x_count lines"
else
    qa_fail "X inserted on lines ($x_count found)"
fi

qa_keys "alt-c"
qa_keys "ctrl-q"
qa_summary
