#!/usr/bin/env bash
# QA-TREE-007: Esc returns focus from tree to editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-007: Tree Esc returns to editor"

file=$(qa_tmpfile_nl "tree007.txt" "editor content")
qa_start "$file"

# Open tree
qa_keys "ctrl-b"
sleep 0.3

# Navigate tree
qa_keys "down" 0.2
qa_keys "down" 0.2

# Esc should return to editor
qa_keys "escape"
sleep 0.2

# Type — should go to editor, not tree
qa_send "x"
qa_assert_screen "editor content" "editor has focus after Esc"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
