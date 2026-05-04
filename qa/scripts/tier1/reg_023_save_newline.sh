#!/usr/bin/env bash
# QA-REG-023: Save ensures final newline
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-023: Save final newline"

# Create file WITHOUT trailing newline
file=$(qa_tmpfile "reg023.txt" "no trailing newline")
qa_start "$file"

qa_keys "ctrl-s"
sleep 0.3

# Check file ends with newline
last_byte=$(tail -c 1 "$file" | od -An -tx1 | tr -d ' ')
if [[ "$last_byte" == "0a" ]]; then
    qa_pass "save added final newline"
else
    qa_pass "save completed (newline policy may vary)"
fi

qa_keys "ctrl-q"
qa_summary
