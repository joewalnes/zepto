#!/usr/bin/env bash
# QA-PRMT-012: Error messages use consistent style
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-012: Error message style"

# Create read-only file
file=$(qa_tmpfile_nl "prmt012.txt" "original")
chmod 444 "$file"
qa_start "$file"

qa_send "edit"
qa_keys "ctrl-s"
sleep 0.5

qa_screen
# Should show error without Perl trace
if echo "$QA_SCREEN" | grep -qE "Save failed|Permission|denied|error"; then
    qa_pass "user-friendly error message shown"
elif echo "$QA_SCREEN" | grep -qE "at .*\.pm line"; then
    qa_fail "Perl stack trace leaked to user"
else
    qa_skip "error message format unclear"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
