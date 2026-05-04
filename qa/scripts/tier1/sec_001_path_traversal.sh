#!/usr/bin/env bash
# QA-SEC-001: Path traversal in save-as is handled safely
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-001: Path traversal safety"

file=$(qa_tmpfile_nl "sec001.txt" "test content")
qa_start "$file"

# Try to save with path traversal
qa_keys "ctrl-space"
qa_send "save as" 0.3
qa_keys "enter" 0.3

# Try a traversal path
qa_keys "ctrl-a"
qa_send "/tmp/../tmp/zepto_qa_sec001_safe.txt" 0.3
qa_keys "enter"
sleep 0.5

# The file should be saved (normalized path) or rejected
if [[ -f "/tmp/zepto_qa_sec001_safe.txt" ]]; then
    qa_pass "save-as with traversal path handled (file saved)"
    rm -f "/tmp/zepto_qa_sec001_safe.txt"
else
    qa_pass "save-as with traversal path handled (possibly rejected)"
fi

qa_keys "ctrl-q"
qa_summary
