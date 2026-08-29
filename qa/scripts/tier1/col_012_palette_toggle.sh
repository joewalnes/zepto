#!/usr/bin/env bash
# QA-COL-012: Column mode respected in palette toggle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-012: Column mode via palette"

file=$(qa_tmpfile_nl "col012.txt" "hello")
qa_start "$file"

# Open palette and toggle column mode
qa_keys "ctrl-space"
qa_send "column" 0.3
qa_keys "enter"

qa_assert_expect "COL" "column mode toggled on via palette"

# Toggle off via palette
qa_keys "ctrl-space"
qa_send "column" 0.3
qa_keys "enter"
sleep 0.3

qa_assert_not_screen "COL" "column mode toggled off via palette"

qa_keys "ctrl-q"
qa_summary
