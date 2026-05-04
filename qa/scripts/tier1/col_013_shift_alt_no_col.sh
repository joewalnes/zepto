#!/usr/bin/env bash
# QA-COL-013: Shift+Alt+Arrow does NOT enter column mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-013: Shift+Alt+Right = word select, not column"

file=$(qa_tmpfile_nl "col013.txt" "hello world foo bar")
qa_start "$file"

# Shift+Alt+Right should select by word, NOT enter column mode
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# Verify no COL indicator
qa_assert_not_screen "COL" "column mode NOT entered from shift-arrow"

qa_keys "ctrl-q"
qa_summary
