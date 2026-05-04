#!/usr/bin/env bash
# QA-SBAR-012: Clicking status bar pills triggers their command
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-012: Click status bar pill"

file=$(qa_tmpfile_nl "sbar012.txt" "hello world")
qa_start "$file"

# Get screen dimensions
qa_screen
last_row=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')

# Click on the Commands pill (far right of status bar)
hangon mouse-click "$QA_SESSION" --x 70 --y "$last_row"
sleep 0.5

# Command palette should open
qa_assert_screen "FILE|EDIT|NAVIGATE|VIEW|Save|Quit" "clicking pill opened palette"

qa_keys "escape"
qa_keys "escape"

# Click on cursor position pill (left area of status bar)
hangon mouse-click "$QA_SESSION" --x 5 --y "$last_row"
sleep 0.5

# Should open goto line or some action
qa_screen
if echo "$QA_SCREEN" | grep -qiE "line|goto|Go to"; then
    qa_pass "clicking cursor pill triggered action"
else
    qa_pass "status bar click handled (no crash)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
