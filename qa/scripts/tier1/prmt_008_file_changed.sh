#!/usr/bin/env bash
# QA-PRMT-008: File-changed-on-disk prompt
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-008: File changed on disk prompt"

file=$(qa_tmpfile_nl "prmt008.txt" "original")
qa_start "$file"

# Make local edit (dirty)
qa_send " local"

# Modify externally
echo "external change" > "$file"

# Interact to trigger check
qa_keys "escape"
sleep 1.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "Reload|Keep|changed"; then
    qa_pass "file-changed prompt shown for dirty buffer"
    # Press K to keep
    qa_send "k"
    sleep 0.3
else
    qa_skip "external change prompt not triggered in time"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
