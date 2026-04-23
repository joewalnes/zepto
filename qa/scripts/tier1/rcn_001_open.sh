#!/usr/bin/env bash
# QA-RCN-001: Ctrl+E opens recent files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-001: Recent files list"

file=$(qa_tmpfile_nl "rcn001.txt" "hello")
qa_start "$file"

qa_keys "ctrl-e"
sleep 0.3

qa_assert_screen "Recent|recent|rcn001" "recent files list visible"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
