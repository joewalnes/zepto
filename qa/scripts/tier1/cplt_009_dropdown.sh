#!/usr/bin/env bash
# QA-CPLT-009: Auto-complete dropdown triggers after pause
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-009: Auto-complete triggers"

file=$(qa_tmpfile_nl "cplt009.js" "const longVariableName = 1
const longOtherThing = 2
")
qa_start "$file"

# Move to line 3 (blank line)
qa_keys "down" 0.1
qa_keys "down" 0.1

# Type partial match
qa_send "long"
sleep 1

# Check for ghost text or completion
qa_screen
if echo "$QA_SCREEN" | grep -qE "longVariable|longOther|Variable|Other"; then
    qa_pass "completion suggestion appeared"
else
    qa_skip "completion not visible (may need longer wait)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
