#!/usr/bin/env bash
# QA-PRMT-003: Cancel quit returns to editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-003: Cancel quit"

file=$(qa_tmpfile_nl "prmt003.txt" "original")
qa_start "$file"

# Modify file
qa_send " changed"
sleep 0.2

# Try to quit
qa_keys "ctrl-q"
sleep 0.3

# Cancel with Escape
qa_keys "escape" 0.3

# Editor should still be running with content visible
qa_assert_expect "original" "editor still showing content after cancel"

# Clean quit
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
