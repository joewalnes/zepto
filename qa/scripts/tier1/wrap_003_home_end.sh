#!/usr/bin/env bash
# QA-WRAP-003: Home/End behavior on wrapped lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-003: Wrap Home/End"

# Create file with a very long line
long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap003.txt" "$long_line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Go to end of line
qa_keys "end"
qa_cursor_pos
end_col="$QA_CURSOR_COL"

# Home should go to start
qa_keys "home"
qa_cursor_pos
if [[ "$QA_CURSOR_COL" -le 2 ]]; then
    qa_pass "home went to start of line (col $QA_CURSOR_COL)"
else
    qa_fail "home went to start of line (col $QA_CURSOR_COL)"
fi

# Toggle wrap back
qa_keys "alt-z"

qa_keys "ctrl-q"
qa_summary
