#!/usr/bin/env bash
# QA-CMT-008: Toggle comment on .txt file (no syntax) — uses # or is no-op
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-008: Plain text comment"

file=$(qa_tmpfile_nl "cmt008.txt" "plain text line")
qa_start "$file"

qa_raw $'\x1f'

# Should either add # prefix or be a no-op
qa_assert_expect "# plain text|plain text line" "toggle comment on .txt handled gracefully"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
