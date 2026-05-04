#!/usr/bin/env bash
# QA-FIND-022: Empty find pattern shows no matches (no crash)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-022: Empty find pattern"

file=$(qa_tmpfile_nl "find022.txt" "hello world")
qa_start "$file"

qa_keys "ctrl-f"
sleep 0.3

# Don't type anything — empty pattern
qa_screen
# Editor should be alive with find bar open, no crash
if qa_alive 2>/dev/null; then
    qa_pass "empty find pattern — no crash"
else
    qa_fail "empty find pattern caused crash"
fi

# Press Enter with empty pattern
qa_keys "enter" 0.3

if qa_alive 2>/dev/null; then
    qa_pass "enter on empty find — no crash"
else
    qa_fail "enter on empty find caused crash"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
