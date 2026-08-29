#!/usr/bin/env bash
# QA-FIND-005: Tab in find activates replace field
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-005: Tab activates replace"

file=$(qa_tmpfile_nl "find005.txt" "hello world")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "hello"
qa_keys "tab"

qa_assert_expect "Replace" "replace field visible"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
