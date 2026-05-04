#!/usr/bin/env bash
# QA-TAB-002: Switch tabs with Alt+. and Alt+,
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-002: Tab switch Alt+. Alt+,"

file1=$(qa_tmpfile_nl "tab002_a.txt" "ALPHA_CONTENT")
file2=$(qa_tmpfile_nl "tab002_b.txt" "BETA_CONTENT")
qa_start "$file1" "$file2"

# Should start on tab 1
qa_assert_screen "ALPHA_CONTENT" "starts on tab 1"

# Alt+. to next tab
qa_keys "alt-."
qa_assert_screen "BETA_CONTENT" "alt-. switched to tab 2"

# Alt+, back
qa_keys "alt-,"
qa_assert_screen "ALPHA_CONTENT" "alt-, switched back to tab 1"

qa_keys "ctrl-q"
qa_summary
