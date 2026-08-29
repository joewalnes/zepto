#!/usr/bin/env bash
# QA-MS-013: Click on status bar pill executes action
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-013: Click status bar pill"

file=$(qa_tmpfile_nl "ms013.txt" "hello world")
qa_start "$file"

# Get screen dimensions to find the Commands pill (rightmost, last row)
qa_screen
last_row=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')

# Click "Commands" pill at far right of last row
hangon mouse-click "$QA_SESSION" --x 70 --y "$last_row"
sleep 0.5

# Command palette should open
qa_assert_expect "FILE|EDIT|NAVIGATE|VIEW|Save|Quit" "clicking Commands pill opens palette"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
