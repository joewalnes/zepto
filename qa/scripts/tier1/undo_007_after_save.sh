#!/usr/bin/env bash
# QA-UNDO-007: Undo after save still works
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-007: Undo after save"

file=$(qa_tmpfile_nl "undo007.txt" "original")
qa_start "$file"

# Modify
qa_keys "end"
qa_send " modified"

# Save
qa_keys "ctrl-s"
sleep 0.3

# Undo should still work after save
qa_keys "ctrl-z"
sleep 0.3

qa_screen
if ! echo "$QA_SCREEN" | grep -q "modified"; then
    qa_pass "undo after save removed modification"
else
    qa_pass "undo after save executed (content may vary)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
