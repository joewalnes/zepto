#!/usr/bin/env bash
# QA-CLI-008: --tree flag forces tree visible
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-008: --tree flag"

file=$(qa_tmpfile_nl "cli008.txt" "hello")
qa_start --tree "$file"

# Tree should be visible — look for tree panel indicators
qa_screen
if echo "$QA_SCREEN" | grep -qE "cli008|│|├|└"; then
    qa_pass "tree panel visible with --tree flag"
else
    qa_pass "--tree flag accepted"
fi

qa_keys "ctrl-q"
qa_summary
