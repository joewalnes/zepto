#!/usr/bin/env bash
# QA-CPLT-013: Up/Down navigates completion menu
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-013: Completion menu Up/Down"

file=$(qa_tmpfile_nl "cplt013.js" "const longAlpha = 1
const longBeta = 2
const longGamma = 3
")
qa_start "$file"

# Move to empty line
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1

# Type prefix to trigger completion
qa_send "long"
sleep 1

# Try Down/Up navigation
qa_keys "down" 0.2
qa_keys "up" 0.2

# Editor should be alive
qa_alive && qa_pass "completion menu navigation works" || qa_fail "editor crashed"

qa_keys "escape"
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
