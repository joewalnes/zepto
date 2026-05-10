#!/usr/bin/env bash
# QA-CPLT-003: Typing [ inserts []
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-003: Auto-pair bracket []"

file=$(qa_tmpfile "cplt003.js" "")
qa_start "$file"

qa_send "["
qa_screen
if echo "$QA_SCREEN" | grep -qF "[]"; then
    qa_pass "[ auto-paired to []"
else
    qa_fail "[ auto-paired to []"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
