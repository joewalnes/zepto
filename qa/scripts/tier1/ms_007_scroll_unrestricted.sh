#!/usr/bin/env bash
# QA-MS-007: Scroll wheel unrestricted past cursor (REGRESSION)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-007: Scroll past cursor position"

content=""
for i in $(seq 1 200); do content+="line $i of the test file"$'\n'; done
file=$(qa_tmpfile_nl "ms007.txt" "$content")
qa_start "$file"

# Cursor starts at 1:1
qa_assert_expect "1:1" "cursor at 1:1"

# Scroll down a lot — cursor should stay at 1:1 but viewport moves
hangon mouse-scroll "$QA_SESSION" --x 20 --y 10 --delta 50
sleep 0.3

# High line numbers should be visible
qa_assert_expect "line (4[0-9]|5[0-9]|6[0-9])" "viewport scrolled past initial screen"

qa_keys "ctrl-q"
qa_summary
