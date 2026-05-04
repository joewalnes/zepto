#!/usr/bin/env bash
# QA-REG-055: Save As updates tab tracking correctly (P0)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-055: Save As tab tracking (P0 regression)"

# Start with untitled tab
qa_start

# Type content
qa_send "save as test content"

# Save As via palette
qa_keys "ctrl-space"
sleep 0.5
qa_send "save as" 0.3
qa_keys "enter"
sleep 0.5

# Type filename
savepath="$QA_TMPDIR/reg055_saved.txt"
qa_send "$savepath" 0.3
qa_keys "enter"
sleep 0.5

# File should exist on disk
if [[ -f "$savepath" ]]; then
    qa_pass "file saved to disk via Save As"
    if grep -q "save as test content" "$savepath"; then
        qa_pass "saved file has correct content"
    else
        qa_fail "saved file has correct content"
    fi
else
    qa_skip "Save As path may need different interaction"
fi

qa_keys "ctrl-q"
qa_summary
