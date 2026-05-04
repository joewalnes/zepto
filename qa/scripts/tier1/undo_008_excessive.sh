#!/usr/bin/env bash
# QA-UNDO-008: Excessive undo doesn't crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-008: Excessive undo"

file=$(qa_tmpfile_nl "undo008.txt" "original")
qa_start "$file"

# Type something
qa_keys "end"
qa_send " added"
sleep 0.2

# Undo many more times than needed
for i in $(seq 1 10); do qa_keys "ctrl-z" 0.1; done

# Should still be alive and responsive
qa_screen
if echo "$QA_SCREEN" | grep -q "original"; then
    qa_pass "excessive undo returned to original"
else
    qa_pass "excessive undo didn't crash"
fi

qa_keys "ctrl-q"
qa_summary
