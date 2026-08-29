#!/usr/bin/env bash
# QA-TAB-001: Open two files shows tab bar with two tabs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-001: Multiple tabs"

file1=$(qa_tmpfile_nl "tab001_a.txt" "content of file A")
file2=$(qa_tmpfile_nl "tab001_b.txt" "content of file B")
qa_start "$file1" "$file2"

# Both filenames should be in tab bar (first row)
qa_assert_expect "tab001_a" "tab A visible"
qa_assert_expect "tab001_b" "tab B visible"

# First file should be active — its content shown
qa_assert_expect "content of file A" "file A content displayed"

# Switch to next tab (Alt+. = ESC then .)
qa_keys "alt-."
qa_assert_expect "content of file B" "file B content after tab switch"

# Switch back (Alt+, = ESC then ,)
qa_keys "alt-,"
qa_assert_expect "content of file A" "file A content after switching back"

qa_keys "ctrl-q"

qa_summary
