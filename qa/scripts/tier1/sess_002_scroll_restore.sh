#!/usr/bin/env bash
# QA-SESS-002: Scroll position restored exactly (not just cursor)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-002: Scroll position restore"

qa_project; dir="$QA_PROJECT_DIR"
seq -f 'line%03g' 1 200 > long.txt

qa_start
qa_keys "ctrl-o"
qa_send "long.txt" 0.3
qa_keys "enter" 0.3

for i in 1 2 3 4 5; do
    qa_keys "pagedown" 0.15
done
qa_assert_screen "line081" "scrolled well past the top before quit"
qa_assert_not_screen "line001" "line 1 no longer visible before quit"

qa_keys "ctrl-q"
sleep 0.4

qa_restart
qa_wait_screen "line081" 5

qa_assert_screen "line081" "viewport reopens at the same scroll position"
qa_assert_not_screen "^ *1 line001" "did not snap back to the top of the file"

qa_keys "ctrl-q"
qa_summary
