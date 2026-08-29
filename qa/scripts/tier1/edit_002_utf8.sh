#!/usr/bin/env bash
# QA-EDIT-002: Insert UTF-8 characters
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-002: UTF-8 input"

file=$(qa_tmpfile "edit002.txt" "")
qa_start "$file"

qa_send "café"
qa_assert_expect "café" "UTF-8 text displayed correctly"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
