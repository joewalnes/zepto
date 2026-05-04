#!/usr/bin/env bash
# QA-COL-002: Typing in column mode inserts on all lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-002: Column mode typing"

file=$(qa_tmpfile_nl "col002.txt" "aaaa
bbbb
cccc
dddd")
qa_start "$file"

# Toggle column mode
qa_keys "alt-c"
sleep 0.2

# Select down 3 lines
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1
sleep 0.2

# Type to insert on all lines
qa_send "X"
sleep 0.3

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
x_count=$(echo "$content" | grep -c "X" || true)
if [[ "$x_count" -ge 3 ]]; then
    qa_pass "column mode inserted X on $x_count lines"
else
    qa_fail "column mode inserted X on $x_count lines (expected 3+)"
fi

# Toggle off
qa_keys "alt-c"

qa_keys "ctrl-q"
qa_summary
