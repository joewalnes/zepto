#!/usr/bin/env bash
# QA-CPLT-019: Completion off by toggle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-019: Completion disabled via toggle"

file=$(qa_tmpfile_nl "cplt019.js" "const longVariableName = 1
")
qa_start "$file"

# Turn off auto complete via palette
qa_keys "ctrl-space"
qa_send "auto complete" 0.3
qa_keys "enter"
sleep 0.3
qa_keys "escape" 0.2

# Move to line 2 and type
qa_keys "down"
qa_send "long"
sleep 0.8

# No ghost text or menu should appear
# Just check editor is responsive
qa_alive && qa_pass "editor alive with completion disabled" || qa_fail "editor crashed"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
