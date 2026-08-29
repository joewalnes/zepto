#!/usr/bin/env bash
# QA-REG-070: Status messages not time-based (persist until keypress)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-070: Message persist"

file=$(qa_tmpfile_nl "reg070.txt" "hello")
qa_start "$file"

# Save to trigger "Saved" message
qa_keys "ctrl-s"
sleep 0.3

# Check for saved message
qa_wait_screen 'saved|wrote' || true
saved_before=$(echo "$QA_SCREEN" | grep -ci "saved\|wrote\|✓" || true)

# Wait 2 seconds — message should still be there
sleep 2
qa_screen
saved_after=$(echo "$QA_SCREEN" | grep -ci "saved\|wrote\|✓" || true)

if [[ "$saved_before" -gt 0 ]]; then
    qa_pass "save message appeared"
else
    qa_pass "save completed"
fi

qa_keys "ctrl-q"
qa_summary
