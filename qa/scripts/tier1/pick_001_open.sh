#!/usr/bin/env bash
# QA-PICK-001: Ctrl+O opens file picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-001: File picker opens"

file=$(qa_tmpfile_nl "pick001.txt" "hello")
qa_start "$file"

qa_keys "ctrl-o"
sleep 0.3

# Picker should show file list or "Open File" prompt
qa_screen
if echo "$QA_SCREEN" | grep -qE "\.sh|\.txt|\.py|\.pm|Makefile|Open|pick001"; then
    qa_pass "file picker visible with file entries"
else
    qa_fail "file picker visible with file entries"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
