#!/usr/bin/env bash
# QA-NAV-016: Arrow exits multi-cursor mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-016: Arrow exits multi-cursor"

file=$(qa_tmpfile_nl "nav016.txt" "foo bar foo baz foo")
qa_start "$file"

# Select first foo and add next occurrence
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Press Right arrow to exit multi-cursor
qa_keys "right"

# Should show only single cursor position (no "2 cursors" / "3 cursors")
qa_assert_not_screen "cursors" "multi-cursor indicator cleared"

qa_keys "ctrl-q"
qa_summary
