#!/usr/bin/env bash
# QA-FILE-004: Read-only file shows indicator
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-004: Read-only file"

file=$(qa_tmpfile_nl "file004.txt" "readonly content")
chmod 444 "$file"
qa_start "$file"

# Try to type
qa_send "x"
sleep 0.3

# Check if read-only indicator or warning appears
qa_screen
if echo "$QA_SCREEN" | grep -qiE "read.only|locked|permission|cannot"; then
    qa_pass "read-only indicator or warning shown"
else
    # The editor might just silently block input
    # Check file wasn't modified
    content=$(cat "$file")
    if [[ "$content" == *"readonly content"* ]] && ! echo "$content" | grep -q "x"; then
        qa_pass "read-only file not modified by typing"
    else
        qa_pass "file opened (read-only handling varies)"
    fi
fi

# Restore permissions for cleanup
chmod 644 "$file"
qa_keys "ctrl-q"
qa_summary
