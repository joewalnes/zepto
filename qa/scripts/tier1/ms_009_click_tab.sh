#!/usr/bin/env bash
# QA-MS-009: Click on tab bar switches tabs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-009: Click tab switches"

file1=$(qa_tmpfile_nl "ms009_a.txt" "content A")
file2=$(qa_tmpfile_nl "ms009_b.txt" "content B")
qa_start "$file1" "$file2"

qa_assert_screen "content A" "starts on tab A"

# Tab B should be visible in tab bar (row 1). Find its position.
# Tab A starts ~col 2, tab B follows after tab A label.
# Tab A: " ◢ ms009_a.txt ⌥1 ×◣ " is ~20 chars
# Click roughly at col 28 row 1 for tab B
hangon mouse-click "$QA_SESSION" --x 28 --y 1
sleep 0.3

qa_assert_screen "content B" "clicking tab B shows content B"

# Click back on tab A (col ~8, row 1)
hangon mouse-click "$QA_SESSION" --x 8 --y 1
sleep 0.3

qa_assert_screen "content A" "clicking tab A shows content A"

qa_keys "ctrl-q"
qa_summary
