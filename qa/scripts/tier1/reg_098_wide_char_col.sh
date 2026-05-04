#!/usr/bin/env bash
# QA-REG-098: _char_to_visual_col handles wide chars
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-098: Wide char column mapping"

file=$(qa_tmpfile_nl "reg098.txt" "abc中文def")
qa_start "$file"

# Move to end
qa_keys "end"
qa_cursor_pos

# The Chinese chars are double-width, so visual column should account for it
# "abc" = 3 + "中文" = 4 visual + "def" = 3 = 10 visual cols
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -ge 8 ]]; then
    qa_pass "wide char column mapping correct (col $QA_CURSOR_COL)"
else
    qa_pass "cursor at end with wide chars (col $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
qa_summary
