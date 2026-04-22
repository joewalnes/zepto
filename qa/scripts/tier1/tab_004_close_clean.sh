#!/usr/bin/env bash
# QA-TAB-004: Close tab with Ctrl+W (clean buffer)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-004: Close clean tab"

file1=$(qa_tmpfile_nl "tab004_a.txt" "file A")
file2=$(qa_tmpfile_nl "tab004_b.txt" "file B")
file3=$(qa_tmpfile_nl "tab004_c.txt" "file C")
qa_start "$file1" "$file2" "$file3"

# Three tabs visible
qa_assert_screen "tab004_a" "tab A visible"
qa_assert_screen "tab004_c" "tab C visible"

# Switch to tab 2 and close it
qa_keys "alt-."
qa_assert_screen "file B" "file B active"

qa_keys "ctrl-w"
sleep 0.3

# Tab B should be gone, and a neighbor tab should be active
qa_assert_not_screen "file B" "file B content gone after close"
qa_assert_screen "tab004_a|tab004_c" "remaining tabs still visible"

qa_keys "ctrl-q"

qa_summary
