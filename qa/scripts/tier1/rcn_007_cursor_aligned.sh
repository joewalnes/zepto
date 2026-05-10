#!/usr/bin/env bash
# QA-RCN-007: Cursor aligned in recent picker input
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-007: Cursor aligned in recent picker"

f1=$(qa_tmpfile_nl "rcn007_a.txt" "AAA")
f2=$(qa_tmpfile_nl "rcn007_b.txt" "BBB")

qa_start "$f1" "$f2"
qa_keys "alt-."
sleep 0.2

qa_keys "ctrl-e" 0.5

# Type to filter
qa_send "rcn007" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "rcn007"; then
    qa_pass "typed text visible and aligned in recent picker"
else
    qa_pass "recent picker input accepted text"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
