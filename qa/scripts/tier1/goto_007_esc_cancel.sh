#!/usr/bin/env bash
# QA-GOTO-007: Esc cancels goto without moving cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-007: Goto Esc cancels"

content=""
for i in $(seq 1 20); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto007.txt" "$content")
qa_start "$file"

# Open goto, type a number, then Esc
qa_keys "ctrl-g"
qa_send "15" 0.2
qa_keys "escape"
sleep 0.3

# Goto bar should be closed — verify editor is responsive
qa_assert_expect "line 1" "goto cancelled, still showing original content"

qa_keys "ctrl-q"
qa_summary
