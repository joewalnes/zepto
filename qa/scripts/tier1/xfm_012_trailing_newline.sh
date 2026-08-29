#!/usr/bin/env bash
# QA-XFM-012: Preserves trailing newline behavior
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-012: Transform preserves trailing newline"

file=$(qa_tmpfile_nl "xfm012.txt" "line one
line two")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Transform with tee (no-op)
qa_keys "alt-t"
qa_keys "ctrl-a" 0.1
qa_send "tee" 0.2
qa_keys "enter"
sleep 0.5

qa_assert_expect "line one" "first line preserved"
qa_assert_expect "line two" "second line preserved"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
