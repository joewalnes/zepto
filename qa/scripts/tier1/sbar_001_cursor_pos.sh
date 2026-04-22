#!/usr/bin/env bash
# QA-SBAR-001: Cursor position pill updates on movement
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-001: Cursor position pill"

file=$(qa_tmpfile_nl "sbar001.txt" "abcdef
ghijkl
mnopqr")
qa_start "$file"

qa_assert_screen "1:1" "starts at 1:1"

qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

qa_assert_screen "3:6" "moved to 3:6"

qa_keys "ctrl-q"
qa_summary
