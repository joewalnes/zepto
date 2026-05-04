#!/usr/bin/env bash
# QA-REG-069: Column selection skips wrap continuation rows
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-069: Column + wrap"

long=$(python3 -c "print('word ' * 40)")
file=$(qa_tmpfile_nl "reg069.txt" "$long
short line
another short")
qa_start "$file"

# Enable wrap then column mode
qa_keys "alt-z"
sleep 0.2
qa_keys "alt-c"
sleep 0.2

# Select down — shouldn't crash
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1
sleep 0.2

if qa_alive; then
    qa_pass "column + wrap selection doesn't crash"
else
    qa_fail "column + wrap crashed"
fi

qa_keys "alt-c"
qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
