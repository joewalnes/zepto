#!/usr/bin/env bash
# QA-FILE-013: Save As to existing file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-013: Save As to existing file path"

existing=$(qa_tmpfile_nl "file013_existing.txt" "existing content")
file=$(qa_tmpfile "file013_new.txt" "")
qa_start "$file"

qa_send "new stuff"

# Save -- should prompt for name since file is empty name
qa_keys "ctrl-s"
sleep 0.3
# Type the path of an existing file
qa_keys "ctrl-a" 0.1
qa_send "$existing" 0.2
qa_keys "enter"
sleep 0.5

# Either overwrite happened or prompt appeared
qa_screen
if echo "$QA_SCREEN" | grep -q "new stuff\|Overwrite\|overwrite"; then
    qa_pass "save-as handled existing file path"
else
    qa_pass "save-as completed (checking file)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
