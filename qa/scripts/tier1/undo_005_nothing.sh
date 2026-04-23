#!/usr/bin/env bash
# QA-UNDO-005: Nothing to undo message
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-005: Nothing to undo"

file=$(qa_tmpfile_nl "undo005.txt" "clean file")
qa_start "$file"

qa_keys "ctrl-z"
qa_assert_screen "Nothing to undo|Nothing|undo" "nothing to undo message"

qa_keys "ctrl-q"
qa_summary
