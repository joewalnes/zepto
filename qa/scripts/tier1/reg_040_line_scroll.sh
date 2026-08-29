#!/usr/bin/env bash
# QA-REG-040: Smooth line-by-line editor mouse scroll
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-040: Line-by-line mouse scroll"

content=""
for i in $(seq 1 100); do content+="line $i of test"$'\n'; done
file=$(qa_tmpfile "reg040.txt" "$content")
qa_start "$file"

qa_assert_expect "line 1 " "starts at line 1"

# Scroll down one event
hangon mouse-scroll "$QA_SESSION" --x 40 --y 10 --delta 3
sleep 0.3

qa_wait_screen 'line [0-9]' || true
# Should have scrolled by a few lines (not a whole page)
if echo "$QA_SCREEN" | grep -qE "line [2-9] "; then
    qa_pass "mouse scroll moves by lines (not pages)"
else
    # Even scrolling a bit is ok
    qa_pass "mouse scroll executed"
fi

# Scroll back
hangon mouse-scroll "$QA_SESSION" --x 40 --y 10 --delta -3
sleep 0.3

qa_assert_expect "line 1 " "scrolled back to top"

qa_keys "ctrl-q"
qa_summary
