#!/usr/bin/env bash
# QA-EDIT-011: Tab inserts spaces
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-011: Tab inserts spaces"

file=$(qa_tmpfile "edit011.txt" "")
qa_start "$file"

qa_keys "tab"
qa_send "x"

# Cursor should be past the indent
qa_assert_expect "    x|   x" "tab inserted leading spaces before x"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
