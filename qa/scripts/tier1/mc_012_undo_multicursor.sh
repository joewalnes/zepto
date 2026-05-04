#!/usr/bin/env bash
# QA-MC-012: Undo a multi-cursor edit in one step
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-012: Undo multi-cursor edit"

file=$(qa_tmpfile_nl "mc012.txt" "foo bar foo baz foo")
qa_start "$file"

# Select all three "foo" via Ctrl+D
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Replace with X
qa_send "X"
qa_assert_screen "X bar X baz X" "all foo replaced with X"

# Undo
qa_keys "ctrl-z"
qa_assert_screen "foo bar foo baz foo" "undo reverted all in one step"

qa_keys "ctrl-q"
qa_summary
