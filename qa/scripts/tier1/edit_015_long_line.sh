#!/usr/bin/env bash
# QA-EDIT-015: Very long line renders and scrolls
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-015: Very long line"

# Create a 5000 char line
long_line=$(python3 -c "print('x' * 5000)")
file=$(qa_tmpfile_nl "edit015.txt" "$long_line")
qa_start "$file"

# Should open at 1:1
qa_assert_expect "1:1" "opens at 1:1"

# Navigate right many times
for i in $(seq 1 10); do qa_keys "right" 0.05; done

qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -gt 5 ]]; then
    qa_pass "cursor moved right on long line (col $QA_CURSOR_COL)"
else
    qa_fail "cursor moved right on long line (col $QA_CURSOR_COL)"
fi

# End should go to far right — col may show screen position or file position
qa_keys "end"
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -gt 10 ]]; then
    qa_pass "end key moved to end of long line (col $QA_CURSOR_COL)"
else
    qa_fail "end key moved to end of long line (col $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
qa_summary
