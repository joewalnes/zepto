#!/usr/bin/env bash
# QA-STRT-005: Quit prompt persists until answered
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-STRT-005: Quit prompt stays visible"

file=$(qa_tmpfile_nl "strt005.txt" "original")
qa_start "$file"

# Modify buffer
qa_send "edit"

# Quit
qa_keys "ctrl-q"
sleep 0.3

# Prompt should appear
qa_assert_expect "Save|Discard|Cancel" "save prompt visible initially"

# Wait 2 seconds — prompt should persist
sleep 2

qa_assert_expect "Save|Discard|Cancel" "save prompt still visible after 2s"

# Dismiss
qa_send "n" 0.3
qa_assert_exited "editor exits after discard"

qa_summary
