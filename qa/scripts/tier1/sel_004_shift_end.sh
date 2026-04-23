#!/usr/bin/env bash
# QA-SEL-004: Shift+End extends to end of line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-004: Shift+End selects to EOL"

file=$(qa_tmpfile "sel004.txt" "hello world")
qa_start "$file"

qa_keys "shift-end"
qa_send "X"

qa_assert_screen "X" "entire line replaced"
qa_assert_not_screen "hello" "original text gone"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
