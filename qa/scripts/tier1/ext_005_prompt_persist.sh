#!/usr/bin/env bash
# QA-EXT-005: Prompt reappears if not resolved
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-005: External change prompt persists"

file=$(qa_tmpfile_nl "ext005.txt" "original")
qa_start "$file"

# Make dirty
qa_send " local"

# External change
echo "external" > "$file"

# Interact
qa_keys "escape"
sleep 1.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "Reload|Keep|changed"; then
    # Navigate without answering
    qa_keys "down"
    sleep 0.5

    # Prompt should still be there
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "Reload|Keep|changed"; then
        qa_pass "prompt persists until resolved"
    else
        qa_fail "prompt disappeared without resolution"
    fi
    qa_send "k"
else
    qa_skip "external change prompt not triggered"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
