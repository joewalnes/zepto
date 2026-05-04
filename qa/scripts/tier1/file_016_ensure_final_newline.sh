#!/usr/bin/env bash
# QA-FILE-016: ensure_final_newline preference respected
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-016: ensure_final_newline"

file=$(qa_tmpfile "file016.txt" "no newline at end")
qa_start "$file"

qa_keys "ctrl-s"
sleep 0.5

# Check file ends with newline
last_byte=$(tail -c 1 "$file" | od -An -tx1 | tr -d ' ')
if [[ "$last_byte" == "0a" ]]; then
    qa_pass "file ends with newline"
else
    qa_fail "file does not end with newline (last byte: $last_byte)"
fi

qa_keys "ctrl-q"
qa_summary
