#!/usr/bin/env bash
# QA-CLI-003: Open multiple files from CLI
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-003: Multiple files from CLI"

file1=$(qa_tmpfile_nl "cli003_a.txt" "content A")
file2=$(qa_tmpfile_nl "cli003_b.txt" "content B")
qa_start "$file1" "$file2"

qa_assert_screen "cli003_a" "tab A visible"
qa_assert_screen "cli003_b" "tab B visible"
qa_assert_screen "content A" "first file content shown"

qa_keys "alt-."
qa_assert_screen "content B" "second file content after tab switch"

qa_keys "ctrl-q"
qa_summary
