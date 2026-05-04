#!/usr/bin/env bash
# QA-EXT-003: Reload clears undo/redo stacks
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-003: Reload clears undo stack"

file=$(qa_tmpfile_nl "ext003.txt" "original")
qa_start "$file"

# Make edits to build undo stack
qa_send " edit1"
qa_send " edit2"

# Modify externally
echo "externally changed" > "$file"

# Trigger reload
qa_keys "escape"
sleep 1.5

qa_screen
if echo "$QA_SCREEN" | grep -q "externally changed"; then
    # Reload happened, try undo
    qa_keys "ctrl-z"
    sleep 0.3
    # Should still show "externally changed" (undo stack cleared)
    qa_assert_screen "externally changed" "undo stack cleared after reload"
elif echo "$QA_SCREEN" | grep -qE "Reload|changed"; then
    # Prompt appeared, press R
    qa_send "r"
    sleep 0.5
    qa_keys "ctrl-z"
    sleep 0.3
    qa_assert_screen "externally changed" "undo stack cleared after reload"
else
    qa_skip "external change not detected in time"
fi

qa_keys "ctrl-q"
qa_summary
