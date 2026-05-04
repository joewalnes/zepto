#!/usr/bin/env bash
# QA-NAV-013: Cursor affinity on short line up/down nav
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-013: Cursor affinity"

file=$(qa_tmpfile_nl "nav013.txt" "long line of text here
short
another long line here")
qa_start "$file"

# Move cursor to col 15 on line 1
qa_keys "home"
for i in $(seq 1 14); do qa_keys "right" 0.05; done

qa_assert_cursor_at "1:15" "cursor at 1:15"

# Move down to short line
qa_keys "down"
# Cursor should clamp to end of "short" (col 6)
qa_assert_cursor_at "2:6" "cursor clamped to end of short line"

# Move down to long line again
qa_keys "down"
# Cursor affinity should restore col 15
qa_assert_cursor_at "3:15" "cursor affinity restored to col 15"

qa_keys "ctrl-q"
qa_summary
