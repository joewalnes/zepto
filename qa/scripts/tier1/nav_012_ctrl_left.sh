#!/usr/bin/env bash
# QA-NAV-012: Alt+Left jumps to previous word boundary
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-012: Alt+Left word jump"

file=$(qa_tmpfile_nl "nav012.txt" "alpha beta gamma delta")
qa_start "$file"

# Move to end
qa_keys "end"
qa_cursor_pos
end_col="$QA_CURSOR_COL"

# Alt+Left should jump back one word
qa_keys "alt-left" 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -lt "$end_col" ]]; then
    qa_pass "alt-left jumped back from col $end_col to $QA_CURSOR_COL"
else
    qa_fail "alt-left jumped back (was $end_col, now $QA_CURSOR_COL)"
fi

# Another jump
prev="$QA_CURSOR_COL"
qa_keys "alt-left" 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -lt "$prev" ]]; then
    qa_pass "second alt-left jumped from $prev to $QA_CURSOR_COL"
else
    qa_fail "second alt-left (was $prev, now $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
qa_summary
