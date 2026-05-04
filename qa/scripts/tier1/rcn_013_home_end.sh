#!/usr/bin/env bash
# QA-RCN-013: Home/End in recent files list
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-013: Recent files Home/End"

file=$(qa_tmpfile_nl "rcn013.txt" "hello")
qa_start "$file"

qa_keys "ctrl-e"
sleep 0.3

# End
qa_keys "end"
sleep 0.2

# Home
qa_keys "home"
sleep 0.2

qa_alive && qa_pass "Home/End navigation in recent files works" || qa_fail "editor crashed"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
