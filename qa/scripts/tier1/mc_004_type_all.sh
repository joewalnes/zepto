#!/usr/bin/env bash
# QA-MC-004: Multi-cursor type replaces all occurrences
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-004: Multi-cursor type replaces all"

file=$(qa_tmpfile_nl "mc004.txt" "foo bar foo
baz foo end")
qa_start "$file"

# Select first "foo" with Ctrl+D, add second and third
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Type replacement
qa_send "X"

# All "foo" should be replaced with "X"
qa_assert_screen "X bar X" "first line: foo replaced with X"
qa_assert_screen "baz X end" "second line: foo replaced with X"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
