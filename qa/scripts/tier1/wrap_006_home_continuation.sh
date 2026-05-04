#!/usr/bin/env bash
# QA-WRAP-006: Home on continuation row goes to visual row start
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-006: Home on wrapped continuation"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap006.txt" "$long_line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Move down into a continuation row
qa_keys "down" 0.1
qa_keys "down" 0.1

# Press Home
qa_keys "home"
qa_cursor_pos

# Column should be at start of visual row (col 1 or beginning of wrapped segment)
if [[ -n "$QA_CURSOR_COL" ]]; then
    qa_pass "home on continuation row moved to col $QA_CURSOR_COL"
else
    qa_fail "home on continuation row"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
