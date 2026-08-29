#!/usr/bin/env bash
# QA-MC-005: Multi-cursor backspace affects all cursors
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-005: Multi-cursor backspace"

file=$(qa_tmpfile_nl "mc005.txt" "foo bar foo
baz foo end")
qa_start "$file"

# Select all "foo" with Ctrl+D x3
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Type "ABC"
qa_send "ABC"

# Backspace once to get "AB"
qa_keys "backspace"

# All should show "AB"
qa_assert_expect "AB bar AB" "first line: AB after backspace"
qa_assert_expect "baz AB end" "second line: AB after backspace"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
