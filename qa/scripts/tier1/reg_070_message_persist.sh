#!/usr/bin/env bash
# QA-REG-070: Status messages not time-based (persist until keypress)
# docs/UI_GUIDELINES.md: "No time-based temporary messages. Messages
# persist until user dismisses them or they are replaced by a newer
# message." This script asserts that directly: the save message must
# still be on screen after a 2s wait with no further user action.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-070: Message persist"

file=$(qa_tmpfile_nl "reg070.txt" "hello")
qa_start "$file"

# Save to trigger "Saved" message
qa_keys "ctrl-s"
sleep 0.3

qa_wait_screen 'saved|wrote' || true
qa_screen
saved_before=$(echo "$QA_SCREEN" | grep -ci "saved\|wrote\|✓" || true)

if [[ "$saved_before" -gt 0 ]]; then
    qa_pass "save message appeared"
else
    qa_fail "save message appeared" "expected 'saved'/'wrote' text on screen after ctrl-s"
fi

# Wait 2 seconds with no further input — the message must still be
# visible. A time-based message (the regression this guards against)
# would have disappeared by now.
sleep 2
qa_screen
saved_after=$(echo "$QA_SCREEN" | grep -ci "saved\|wrote\|✓" || true)

if [[ "$saved_after" -gt 0 ]]; then
    qa_pass "save message still present after 2s wait (not time-based)"
else
    qa_fail "save message still present after 2s wait (not time-based)" \
        "message count was $saved_before right after save, but $saved_after after a 2s wait with no keypress"
fi

qa_keys "ctrl-q"
qa_summary
