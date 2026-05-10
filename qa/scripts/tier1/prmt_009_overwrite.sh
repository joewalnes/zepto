#!/usr/bin/env bash
# QA-PRMT-009: Save As on existing file behavior
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-009: Save As on existing file"

existing=$(qa_tmpfile_nl "prmt009_existing.txt" "original content")

# Create new tab and try to save to existing file
file=$(qa_tmpfile "prmt009_new.txt" "")
qa_start "$file"

qa_send "new content"

# Save As to the existing file path
qa_keys "ctrl-space"
qa_send "save as" 0.3
qa_keys "enter" 0.3
qa_send "$existing"
qa_keys "enter" 0.5

# Editor should handle this predictably (either prompt or proceed)
if qa_alive 2>/dev/null; then
    qa_pass "Save As on existing file handled gracefully"
else
    qa_fail "Save As on existing file crashed"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
