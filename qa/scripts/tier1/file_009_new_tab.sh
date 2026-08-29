#!/usr/bin/env bash
# QA-FILE-009: Ctrl+N creates new empty tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-009: New tab"

file=$(qa_tmpfile_nl "file009.txt" "existing")
qa_start "$file"

qa_keys "ctrl-n"
qa_assert_expect "untitled" "new untitled tab created"

# Should be empty
qa_assert_expect "1:1" "cursor at 1:1 in new tab"

qa_keys "ctrl-q"
qa_summary
