#!/usr/bin/env bash
# QA-STRT-004: Quit with unsaved changes shows prompt
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-STRT-004: Quit dirty buffer shows save prompt"

file=$(qa_tmpfile_nl "strt004.txt" "original")
qa_start "$file"

qa_send "edit"
qa_keys "ctrl-q"
sleep 0.3

qa_assert_screen "Save|Discard|Cancel" "save prompt visible"

# Discard with N
qa_send "n" 0.3
qa_assert_exited "editor exits after discard"

qa_summary
