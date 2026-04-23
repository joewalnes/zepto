#!/usr/bin/env bash
# QA-COL-001: Alt+C toggles column selection mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-001: Column mode toggle"

file=$(qa_tmpfile_nl "col001.txt" "abcdef
ghijkl
mnopqr")
qa_start "$file"

qa_keys "alt-c"
qa_assert_screen "COL" "COL indicator visible in status bar"

qa_keys "alt-c"
qa_assert_not_screen "COL" "COL indicator gone after second toggle"

qa_keys "ctrl-q"
qa_summary
