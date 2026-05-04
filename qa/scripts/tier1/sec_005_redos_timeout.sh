#!/usr/bin/env bash
# QA-SEC-005: ReDoS protection via execution timeout
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-005: ReDoS timeout protection"

# Create file with content that causes catastrophic backtracking
file=$(qa_tmpfile_nl "sec005.txt" "$(printf 'a%.0s' {1..100})b")
qa_start "$file"

# Open find with regex mode
qa_keys "ctrl-f"
qa_keys "ctrl-r" 0.2

# Type a catastrophic backtracking pattern
qa_send "(a+)+\$" 0.5

# Wait a moment — the SIGALRM should prevent freeze
sleep 2

# Editor should still be responsive
qa_keys "escape"
sleep 0.3
qa_send "x"
sleep 0.3

qa_screen
if qa_alive; then
    qa_pass "editor survived catastrophic regex (timeout protection)"
else
    qa_fail "editor survived catastrophic regex" "process died"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
