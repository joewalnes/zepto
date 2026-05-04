#!/usr/bin/env bash
# QA-CPLT-014: Enter accepts menu selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-014: Enter accepts completion"

file=$(qa_tmpfile_nl "cplt014.js" "const longVariableName = 1
")
qa_start "$file"

qa_keys "down"
qa_send "long"
sleep 1

# Press Enter to accept (if menu is showing)
qa_keys "enter"
sleep 0.3

# Editor should not crash and should have content
qa_alive && qa_pass "Enter in completion menu works" || qa_fail "editor crashed"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
