#!/usr/bin/env bash
# QA-CMT-008: Toggle comment on .txt file (no syntax) — uses # or is no-op
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-008: Plain text comment"

file=$(qa_tmpfile_nl "cmt008.txt" "plain text line")
qa_start "$file"

qa_raw $'\x1f'
qa_screen

# Should either add # prefix or be a no-op
if echo "$QA_SCREEN" | grep -qE "# plain text|plain text line"; then
    qa_pass "toggle comment on .txt handled gracefully"
else
    qa_fail "toggle comment on .txt handled gracefully"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
