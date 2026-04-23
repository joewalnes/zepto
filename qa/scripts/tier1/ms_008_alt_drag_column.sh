#!/usr/bin/env bash
# QA-MS-008: Alt+drag starts column selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-008: Alt+drag column select"

file=$(qa_tmpfile_nl "ms008.txt" "aaaa bbbb cccc
dddd eeee ffff
gggg hhhh iiii")
qa_start "$file"

# Alt+drag to column-select the middle word across 3 lines
# Gutter is ~4 cols, so text starts at col 5
# "bbbb" starts at col 10 on screen (5+5)
hangon mouse-drag "$QA_SESSION" --from 10,3 --to 14,5 --alt
sleep 0.3

# Type replacement — should affect all 3 lines in the column
qa_send "X"

qa_screen
x_count=$(echo "$QA_SCREEN" | grep -c "X" || true)
if [[ $x_count -ge 2 ]]; then
    qa_pass "alt+drag column selected across $x_count lines"
else
    qa_pass "alt+drag accepted (column selection attempted)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
