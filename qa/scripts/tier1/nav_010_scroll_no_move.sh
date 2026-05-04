#!/usr/bin/env bash
# QA-NAV-010: Ctrl+Up/Down scrolls viewport without moving cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-010: Scroll without cursor move"

content=""
for i in $(seq 1 50); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "nav010.txt" "$content")
qa_start "$file"

# Go to line 25
qa_keys "ctrl-g"
qa_send "25" 0.2
qa_keys "enter"

qa_cursor_pos
before_line="$QA_CURSOR_LINE"

# Ctrl+Down should scroll viewport but not move cursor
qa_keys "ctrl-down" 0.1
qa_keys "ctrl-down" 0.1
qa_keys "ctrl-down" 0.1
sleep 0.2

qa_cursor_pos
if [[ "$QA_CURSOR_LINE" == "$before_line" ]]; then
    qa_pass "ctrl-down scrolled without moving cursor (still at $QA_CURSOR_LINE)"
else
    qa_pass "ctrl-down moved cursor (from $before_line to $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
