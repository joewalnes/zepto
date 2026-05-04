#!/usr/bin/env bash
# QA-REG-033: Undo at document boundary doesn't crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-033: Undo at boundary"

file=$(qa_tmpfile "reg033.txt" "")
qa_start "$file"

# Type one character then undo repeatedly
qa_send "x"
sleep 0.2
for i in $(seq 1 5); do qa_keys "ctrl-z" 0.1; done

# Should still be alive
if qa_alive; then
    qa_pass "undo at boundary didn't crash"
else
    qa_fail "undo at boundary crashed editor"
fi

qa_keys "ctrl-q"
qa_summary
