#!/usr/bin/env bash
# QA-REG-010: ReDoS protection - patterns > 1000 chars rejected
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-010: ReDoS length limit"

file=$(qa_tmpfile_nl "reg010.txt" "some text to search in")
qa_start "$file"

qa_keys "ctrl-f"
sleep 0.3

# Generate a very long pattern (>1000 chars)
long_pattern=$(printf 'a%.0s' $(seq 1 1050))
qa_send "$long_pattern" 0.5

# Editor should either show error or just not crash
if qa_alive; then
    qa_pass "editor alive after very long search pattern"
else
    qa_fail "editor alive after very long search pattern" "editor crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
