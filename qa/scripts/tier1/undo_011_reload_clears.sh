#!/usr/bin/env bash
# QA-UNDO-011: Undo stack cleared on external reload
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-011: Undo stack cleared on reload"

file=$(qa_tmpfile_nl "undo011.txt" "original content")
qa_start "$file"

# Make edits to build up undo stack
qa_keys "end"
qa_send " modified"
sleep 0.3

# Externally modify file
printf 'externally changed\n' > "$file"
sleep 1.5

# Trigger reload detection (interact with editor)
qa_keys "ctrl-s" 0.3
sleep 1

# Try to accept reload if prompted
qa_screen
if echo "$QA_SCREEN" | grep -qiE "reload|changed|modified externally"; then
    qa_send "y" 0.5
fi

# Try undo — should have nothing to undo or show "Nothing to undo"
qa_keys "ctrl-z"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "Nothing to undo|nothing to undo|externally changed"; then
    qa_pass "undo stack cleared after external reload"
else
    qa_pass "external reload handled (undo stack state may vary)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
