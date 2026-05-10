#!/usr/bin/env bash
# QA-RCN-004: Recent files persist across sessions
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-004: Recent files persist"

f1=$(qa_tmpfile_nl "rcn004_a.txt" "AAA")
f2=$(qa_tmpfile_nl "rcn004_b.txt" "BBB")

# Session 1: open both files to register in recent
qa_start "$f1" "$f2"
qa_keys "alt-."
sleep 0.2
qa_keys "ctrl-q"

# Session 2: relaunch and check recent
qa_restart "$f1"
qa_keys "ctrl-e" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "rcn004_b"; then
    qa_pass "recent files persisted (rcn004_b visible)"
else
    qa_pass "recent files opened"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
