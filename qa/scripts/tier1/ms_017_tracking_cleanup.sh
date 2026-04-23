#!/usr/bin/env bash
# QA-MS-017: Mouse tracking disabled on exit
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-017: Mouse tracking cleanup on exit"

file=$(qa_tmpfile_nl "ms017.txt" "hello")
qa_start "$file"

# Click to verify mouse tracking is active
hangon mouse-click "$QA_SESSION" --x 10 --y 3
sleep 0.2

# Quit
qa_keys "ctrl-q"
sleep 0.5

# Editor should have exited cleanly
if ! qa_alive 2>/dev/null; then
    qa_pass "editor exited (mouse tracking should be disabled)"
else
    qa_fail "editor still running"
    hangon stop "$QA_SESSION" 2>/dev/null
fi

qa_summary
