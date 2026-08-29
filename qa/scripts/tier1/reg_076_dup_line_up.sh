#!/usr/bin/env bash
# QA-REG-076: Duplicate line up uses Ctrl+U
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-076: Duplicate line up (Ctrl+U)"

file=$(qa_tmpfile_nl "reg076.txt" "original line")
qa_start "$file"

qa_keys "ctrl-u"

# Should have two copies
qa_wait_screen 'original line' || true
count=$(echo "$QA_SCREEN" | grep -c "original line" || true)
if [[ $count -ge 2 ]]; then
    qa_pass "line duplicated up ($count copies)"
else
    qa_fail "line duplicated up" "only $count copy visible"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
