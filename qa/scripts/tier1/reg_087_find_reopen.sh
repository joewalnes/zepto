#!/usr/bin/env bash
# QA-REG-087: Find bar pre-selects previous query on reopen
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-087: Find bar pre-selects previous query"

file=$(qa_tmpfile_nl "reg087.txt" "hello world hello")
qa_start "$file"

# Open find, type query, close
qa_keys "ctrl-f"
qa_send "hello" 0.3
qa_keys "escape"

# Reopen find - should show previous query
qa_keys "ctrl-f"
sleep 0.3

qa_assert_screen "hello" "previous query pre-filled on reopen"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
