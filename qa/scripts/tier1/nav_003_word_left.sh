#!/usr/bin/env bash
# QA-NAV-003: Ctrl+Left moves cursor word left
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-003: Word left"

file=$(qa_tmpfile_nl "nav003.txt" "hello world foo bar")
qa_start "$file"

# Move to end of line
qa_keys "end"
qa_cursor_pos
end_col="$QA_CURSOR_COL"

# Word left should jump to start of "bar"
qa_keys "ctrl-left"
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -lt "$end_col" ]]; then
    qa_pass "ctrl-left moved cursor left (from col $end_col to $QA_CURSOR_COL)"
else
    qa_fail "ctrl-left moved cursor left (was $end_col, now $QA_CURSOR_COL)"
fi

# Another word left
prev_col="$QA_CURSOR_COL"
qa_keys "ctrl-left"
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -lt "$prev_col" ]]; then
    qa_pass "second ctrl-left moved further left (from col $prev_col to $QA_CURSOR_COL)"
else
    qa_fail "second ctrl-left moved further left (was $prev_col, now $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
qa_summary
