#!/usr/bin/env bash
# QA-CPLT-015: Completion menu does not break undo/redo
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-015: Completion undo/redo safe"

file=$(qa_tmpfile_nl "cplt015.js" "const longVariableName = 1
")
qa_start "$file"

# Move to line 2 and type
qa_keys "down"
qa_send "long"
sleep 1

# Accept completion if available
qa_keys "tab"
sleep 0.3

# Undo
qa_keys "ctrl-z"
sleep 0.3

# Redo
qa_keys "ctrl-y"
sleep 0.3

# Editor should be alive, no warnings
qa_alive && qa_pass "undo/redo after completion without crash" || qa_fail "editor crashed"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
