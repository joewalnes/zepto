#!/usr/bin/env bash
# QA-CLI-008: --tree flag forces tree visible
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-008: --tree flag"

file=$(qa_tmpfile_nl "cli008.txt" "hello")
qa_start --tree "$file"

# Tree should be visible — look for directory entries (dots, names)
qa_assert_screen "lib|docs|src|\\.github" "tree panel shows directory entries"
qa_assert_screen "hello" "editor content still visible"

qa_keys "ctrl-q"
qa_summary
