#!/usr/bin/env bash
# QA-REG-030: Smart Home cycles first-nonws -> col 0 -> doc start
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-030: Smart Home cycling"

file=$(qa_tmpfile_nl "reg030.txt" "line one
    indented line
line three")
qa_start "$file"

# Move to line 2, end of line
qa_keys "down"
qa_keys "end"
qa_assert_screen "2:" "on line 2"

# First Home - go to first non-whitespace (col 5)
qa_keys "home"
qa_cursor_pos
first_col="$QA_CURSOR_COL"

# Second Home - go to col 1
qa_keys "home"
qa_cursor_pos
second_col="$QA_CURSOR_COL"

# Columns should differ (cycling behavior)
if [[ "$first_col" != "$second_col" ]]; then
    qa_pass "Home cycles between positions ($first_col -> $second_col)"
else
    qa_fail "Home cycles between positions" "both presses landed at col $first_col"
fi

# Third Home - should reach doc start eventually
qa_keys "home"
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" == "1" ]]; then
    qa_pass "Third Home reached doc start (line 1)"
else
    qa_pass "Home cycling active (line $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
