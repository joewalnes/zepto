#!/usr/bin/env bash
# QA-MC-007: Arrow key exits multi-cursor mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-007: Arrow exits multi-cursor"

file=$(qa_tmpfile_nl "mc007.txt" "foo bar foo baz foo")
qa_start "$file"

# Select all "foo"
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Press right arrow to exit multi-cursor
qa_keys "right"
sleep 0.2

# Now typing should only affect one cursor
qa_send "X"

# Count X occurrences — should be only 1
qa_screen
x_count=$(echo "$QA_SCREEN" | grep -o "X" | wc -l | tr -d ' ')
if [[ "$x_count" -le 2 ]]; then
    qa_pass "arrow exited multi-cursor (only $x_count X on screen)"
else
    qa_fail "arrow exited multi-cursor" "found $x_count X"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
