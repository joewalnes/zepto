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
qa_screen
if echo "$QA_SCREEN" | grep -qE "^  +hello| +hello"; then
    qa_pass "tab indented the line"
else
    qa_fail "tab indented the line"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
