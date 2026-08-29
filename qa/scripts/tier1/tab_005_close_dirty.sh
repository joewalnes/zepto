#!/usr/bin/env bash
# QA-TAB-005: Close dirty tab shows save prompt
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-005: Close dirty tab prompt"

# Need two tabs so ctrl-w doesn't exit the whole editor
file1=$(qa_tmpfile_nl "tab005a.txt" "file A")
file2=$(qa_tmpfile_nl "tab005b.txt" "file B")
qa_start "$file1" "$file2"
sleep 0.3

# Switch to tab 2 and make it dirty
qa_keys "alt-." 0.5
qa_send "edit" 0.5

# Close dirty tab with Ctrl+W
qa_keys "ctrl-w"
sleep 0.5

qa_assert_expect "Save|Discard|Cancel" "save prompt appears"

# Discard with N — should close tab 2 and switch to tab 1
qa_send "n" 0.3

qa_assert_expect "file A" "tab 1 active after closing tab 2"
qa_assert_not_screen "tab005b" "tab 2 no longer in tab bar"

qa_keys "ctrl-q"
qa_summary
