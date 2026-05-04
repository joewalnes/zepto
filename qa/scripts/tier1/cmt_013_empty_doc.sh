#!/usr/bin/env bash
# QA-CMT-013: Toggle comment on empty document is no-op
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-013: Toggle comment on empty doc"

file=$(qa_tmpfile "cmt013.txt" "")
qa_start "$file"

# Toggle comment on empty buffer
qa_raw $'\x1f'

# Should not crash
qa_alive && qa_pass "editor alive after comment on empty doc" || qa_fail "editor crashed"

qa_keys "ctrl-q"
qa_summary
