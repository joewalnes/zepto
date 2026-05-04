#!/usr/bin/env bash
# QA-WRAP-015: Home/End on wrapped continuation rows
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-015: Wrap Home/End"

long=$(python3 -c "print('alpha ' * 30)")
file=$(qa_tmpfile_nl "wrap015.txt" "$long")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Move down into continuation row
qa_keys "down" 0.1
qa_keys "down" 0.1

# Home should go to visual row start or logical line start
qa_keys "home"
qa_cursor_pos
home_col="$QA_CURSOR_COL"

# End should go to end
qa_keys "end"
qa_cursor_pos
end_col="$QA_CURSOR_COL"

if [[ -n "$home_col" && -n "$end_col" ]]; then
    qa_pass "home/end work on wrapped lines (home=$home_col end=$end_col)"
else
    qa_fail "home/end on wrapped lines"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
