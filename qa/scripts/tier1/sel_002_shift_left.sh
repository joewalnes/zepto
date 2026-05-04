#!/usr/bin/env bash
# QA-SEL-002: Shift+Left extends selection left
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-002: Shift+Left selection"

file=$(qa_tmpfile_nl "sel002.txt" "hello world")
qa_start "$file"

# Move to end
qa_keys "end"

# Shift+Left 5 times to select "world"
for i in $(seq 1 5); do qa_keys "shift-left" 0.05; done

# Type to replace
qa_send "X"

qa_assert_screen "hello X" "shift-left selected and replaced 'world'"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
