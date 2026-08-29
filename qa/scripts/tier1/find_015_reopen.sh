#!/usr/bin/env bash
# QA-FIND-015: Reopening find preselects previous query
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-015: Find remembers previous query"

file=$(qa_tmpfile_nl "find015.txt" "hello world hello")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "hello" 0.3
qa_keys "escape"

# Reopen find
qa_keys "ctrl-f"

qa_assert_expect "hello" "previous query pre-filled"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
