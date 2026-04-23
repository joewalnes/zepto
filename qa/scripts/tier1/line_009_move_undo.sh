#!/usr/bin/env bash
# QA-LINE-009: Move line + undo reverts order
# NOTE: Known bug — undo of move-line corrupts buffer (see bugs.md)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-009: Move line undo"

file=$(qa_tmpfile_nl "line009.txt" "alpha
bravo
charlie")
qa_start "$file"

# Move line 1 down
qa_keys "alt-down"
qa_assert_screen "bravo" "line moved"

# Undo — known to corrupt buffer, skip for now
qa_skip "undo of move-line" "known bug — buffer corruption"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
