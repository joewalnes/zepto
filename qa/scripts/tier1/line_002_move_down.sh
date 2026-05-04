#!/usr/bin/env bash
# QA-LINE-002: Alt+Down moves line down
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-002: Move line down"

file=$(qa_tmpfile_nl "line002.txt" "first
second
third")
qa_start "$file"

# Cursor starts on line 1 (first)
# Move first down — should swap first and second
qa_keys "alt-down"
sleep 0.2

# Save and check file on disk (ground truth)
qa_keys "ctrl-s"
sleep 0.3

line1=$(head -1 "$file")
if [[ "$line1" == "second" ]]; then
    qa_pass "alt-down moved first below second"
else
    qa_fail "alt-down moved first below second (line 1 is '$line1')"
fi

qa_keys "ctrl-q"
qa_summary
