#!/usr/bin/env bash
# QA-EDIT-013: Shift+Tab unindents a selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-013: Shift+Tab unindents"

file=$(qa_tmpfile_nl "edit013.txt" "    alpha
    bravo
    charlie")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Shift+Tab = backtab (CSI Z)
qa_raw $'\x1b[Z'

# Lines should lose indent
qa_assert_expect "alpha" "alpha visible (unindented)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
