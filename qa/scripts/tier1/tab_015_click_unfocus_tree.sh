#!/usr/bin/env bash
# QA-TAB-015: Click a tab unfocuses tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-015: Tab click unfocuses tree"

file=$(qa_tmpfile_nl "tab015.txt" "hello world")
qa_start --tree "$file"

# Focus the tree with Ctrl+B or palette
qa_keys "ctrl-b"
sleep 0.3

# Click on the tab (row 1, col ~20 where tab name would be)
qa_screen
hangon mouse-click "$QA_SESSION" --x 20 --y 1
sleep 0.3

# Should be focused on editor, not tree — type and check
qa_send "X"
qa_assert_screen "X" "typing works after clicking tab (editor focused)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
