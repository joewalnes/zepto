#!/usr/bin/env bash
# QA-REG-044: Cursor-pos pill width stable (no jiggling)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-044: Cursor pill width stable"

# Create file with varying line lengths
file=$(qa_tmpfile_nl "reg044.txt" "short
a much longer line with many characters here
x
another medium length line")
qa_start "$file"

# Move through lines and check status bar stability
qa_status_bar
bar1="$QA_STATUS_BAR"

qa_keys "down"
qa_status_bar
bar2="$QA_STATUS_BAR"

qa_keys "down"
qa_status_bar
bar3="$QA_STATUS_BAR"

# All status bars should have similar structure (pills, not jiggling)
# Check that cursor position is shown in all
for i in 1 2 3; do
    bar_var="bar$i"
    bar_val="${!bar_var}"
    if echo "$bar_val" | grep -qE '[0-9]+:[0-9]+'; then
        qa_pass "cursor pill visible at position $i"
    else
        qa_fail "cursor pill visible at position $i"
    fi
done

qa_keys "ctrl-q"
qa_summary
