#!/usr/bin/env bash
# QA-FIND-017: Invalid regex doesn't crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-017: Invalid regex no crash"

file=$(qa_tmpfile_nl "find017.txt" "hello world")
qa_start "$file"

# Open find, enable regex
qa_keys "ctrl-f"
qa_keys "ctrl-r" 0.2

# Type invalid regex
qa_send "(unbalanced" 0.3

# Should not crash — editor still responsive
qa_keys "escape"
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -q "hello world"; then
    qa_pass "editor still alive after invalid regex"
else
    qa_fail "editor still alive after invalid regex"
fi

qa_keys "ctrl-q"
qa_summary
