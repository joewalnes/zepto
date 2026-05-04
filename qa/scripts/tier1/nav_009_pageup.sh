#!/usr/bin/env bash
# QA-NAV-009: Page Up moves viewport up
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-009: Page Up"

content=""
for i in $(seq 1 100); do content+="line $i here"$'\n'; done
file=$(qa_tmpfile_nl "nav009.txt" "$content")
qa_start "$file"

# Go to bottom
qa_keys "ctrl-g"
qa_send "80" 0.2
qa_keys "enter"

qa_cursor_pos
start_line="$QA_CURSOR_LINE"

# Page up
qa_keys "pageup"
sleep 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -lt "$start_line" ]]; then
    qa_pass "page up moved cursor up (from $start_line to $QA_CURSOR_LINE)"
else
    qa_fail "page up moved cursor up (was $start_line, now $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
