#!/usr/bin/env bash
# QA-MC-001+002+003: Multi-cursor Ctrl+D select, add, and type
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-001: Ctrl+D multi-cursor"

file=$(qa_tmpfile_nl "mc001.txt" "foo bar foo
baz foo qux")
qa_start "$file"

# Cursor on first "foo", Ctrl+D selects it
qa_keys "ctrl-d"
qa_assert_screen "foo" "first foo selected"

# Second Ctrl+D adds next occurrence
qa_keys "ctrl-d"

# Third Ctrl+D adds third
qa_keys "ctrl-d"

# Type replacement
qa_send "X"

# All "foo" should be replaced with "X"
qa_assert_screen "X bar X" "first line: both foo replaced"
qa_assert_screen "baz X qux" "second line: foo replaced"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
