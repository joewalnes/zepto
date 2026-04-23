#!/usr/bin/env bash
# QA-TAB-009: Modified dot appears on first edit
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-009: Modified indicator in tab"

file=$(qa_tmpfile_nl "tab009.txt" "clean")
qa_start "$file"

qa_assert_not_screen "●" "no dot initially"

qa_send "x"
qa_assert_screen "●" "dot appears after edit"

qa_keys "ctrl-z"
qa_assert_not_screen "●" "dot gone after undo"

qa_keys "ctrl-q"
qa_summary
