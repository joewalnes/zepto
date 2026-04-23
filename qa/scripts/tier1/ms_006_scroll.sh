#!/usr/bin/env bash
# QA-MS-006: Scroll wheel scrolls viewport
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-006: Scroll wheel"

content=""
for i in $(seq 1 100); do content+="line $i of the test file"$'\n'; done
file=$(qa_tmpfile_nl "ms006.txt" "$content")
qa_start "$file"

qa_assert_screen "line 1 " "starts showing line 1"

# Scroll down
hangon mouse-scroll "$QA_SESSION" --x 20 --y 10 --delta 10
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "line (1[0-9]|2[0-9])"; then
    qa_pass "scroll down moved viewport"
else
    qa_fail "scroll down moved viewport"
fi

# Scroll back up
hangon mouse-scroll "$QA_SESSION" --x 20 --y 10 --delta -10
sleep 0.3

qa_assert_screen "line 1 " "scroll up returned to top"

qa_keys "ctrl-q"
qa_summary
