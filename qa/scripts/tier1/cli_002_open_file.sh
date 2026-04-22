#!/usr/bin/env bash
# QA-CLI-002: Open single file from CLI
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-002: Open single file shows content"

file=$(qa_tmpfile_nl "cli002.txt" "hello world")
qa_start "$file"

qa_assert_screen "hello world" "file content displayed"
qa_assert_screen "cli002" "filename in tab bar"
qa_assert_screen "1:1" "cursor at 1:1"

qa_keys "ctrl-q"
qa_summary
