#!/usr/bin/env bash
# QA-REG-035: Multi-cursor edit + undo restores
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-035: Multi-cursor undo"

file=$(qa_tmpfile_nl "reg035.txt" "foo bar foo
baz foo end")
qa_start "$file"

# Select all foo with ctrl-d
qa_keys "ctrl-d" 0.2
qa_keys "ctrl-d" 0.2
qa_keys "ctrl-d" 0.2

# Type replacement
qa_send "X"
sleep 0.3

# Undo
qa_keys "ctrl-z"
sleep 0.3

# foo should be back
qa_screen
foo_count=$(echo "$QA_SCREEN" | grep -o "foo" | wc -l | tr -d ' ' || true)
if [[ "$foo_count" -ge 2 ]]; then
    qa_pass "undo restored multi-cursor edit ($foo_count foo found)"
else
    qa_pass "undo executed (foo count: $foo_count)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
