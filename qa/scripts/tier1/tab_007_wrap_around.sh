#!/usr/bin/env bash
# QA-TAB-007: Tab cycling wraps around
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-007: Tab wrap around"

file1=$(qa_tmpfile_nl "tab007_a.txt" "AAA_content")
file2=$(qa_tmpfile_nl "tab007_b.txt" "BBB_content")
qa_start "$file1" "$file2"

# Start on tab 1
qa_assert_screen "AAA_content" "starts on tab 1"

# Go to tab 2
qa_keys "alt-."
qa_assert_screen "BBB_content" "moved to tab 2"

# Next tab should wrap to tab 1
qa_keys "alt-."
qa_assert_screen "AAA_content" "wrapped around to tab 1"

# Prev tab from tab 1 should wrap to tab 2
qa_keys "alt-,"
qa_assert_screen "BBB_content" "prev wrapped to tab 2"

qa_keys "ctrl-q"
qa_summary
