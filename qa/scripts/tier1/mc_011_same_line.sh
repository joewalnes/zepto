#!/usr/bin/env bash
# QA-MC-011: Multi-cursor on same line replaces all
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-011: Multi-cursor same line"

file=$(qa_tmpfile "mc011.txt" "foo foo foo")
qa_start "$file"

# Select all three "foo" on same line
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Type replacement
qa_send "X"

qa_assert_screen "X X X" "all three foo replaced with X on same line"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
