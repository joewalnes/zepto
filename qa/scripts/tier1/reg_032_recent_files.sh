#!/usr/bin/env bash
# QA-REG-032: Recent files via Ctrl+E
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-032: Recent files via Ctrl+E"

file=$(qa_tmpfile_nl "reg032.txt" "content")
qa_start "$file"

qa_keys "ctrl-e"
sleep 0.5

qa_assert_expect "Recent|recent|reg032" "recent files list visible"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
