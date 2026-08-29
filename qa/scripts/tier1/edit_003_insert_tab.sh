#!/usr/bin/env bash
# QA-EDIT-003: Tab key inserts spaces (or tab character)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-003: Tab insertion"

file=$(qa_tmpfile_nl "edit003.txt" "hello")
qa_start "$file"

# Move to start and press tab
qa_keys "home"
qa_keys "tab"

# Line should now be indented
qa_assert_expect "  +hello| +hello" "tab indented the line"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
