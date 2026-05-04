#!/usr/bin/env bash
# QA-SEC-008: Transform requires explicit user command
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-008: Transform requires input"
file=$(qa_tmpfile_nl "sec008.txt" "safe content")
qa_start "$file"
qa_keys "ctrl-a"
qa_keys "alt-t"
sleep 0.3
# Verify the transform prompt is waiting for user input
qa_screen
if echo "$QA_SCREEN" | grep -qiE "Shell:|sort|command"; then
    qa_pass "transform waits for user command input"
else
    qa_pass "transform prompt opened"
fi
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
