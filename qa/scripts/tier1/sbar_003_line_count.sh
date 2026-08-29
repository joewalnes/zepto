#!/usr/bin/env bash
# QA-SBAR-003: Status bar shows cursor position and file info
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-003: Status bar info"

content=""
for i in $(seq 1 25); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "sbar003.txt" "$content")
qa_start "$file"

# Status bar should show cursor position pill
qa_assert_expect "1:1" "cursor position 1:1 shown"

# Navigate to line 10
qa_keys "ctrl-g"
qa_send "10" 0.2
qa_keys "enter"

# Status bar should update to show 10:1
qa_assert_expect "10:1" "cursor position updated to 10:1"

qa_keys "ctrl-q"
qa_summary
