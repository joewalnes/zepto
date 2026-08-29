#!/usr/bin/env bash
# QA-MS-008: Alt+drag activates column selection mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-008: Alt+drag column select"

file=$(qa_tmpfile_nl "ms008.txt" "aaaa bbbb cccc
dddd eeee ffff
gggg hhhh iiii")
qa_start "$file"

# Alt+drag should activate COL mode
hangon mouse-drag "$QA_SESSION" --from 10,3 --to 14,5 --alt --steps 5
sleep 0.3

# COL indicator should appear in status bar
qa_assert_expect "COL" "alt+drag activated column mode"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
