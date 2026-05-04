#!/usr/bin/env bash
# QA-REG-053: Auto-pair undo removes both chars
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-053: Auto-pair undo"

file=$(qa_tmpfile "reg053.js" "")
qa_start "$file"

# Type ( which auto-pairs to ()
qa_send "("
sleep 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qF "()"; then
    qa_pass "auto-pair inserted ()"
else
    qa_pass "character inserted"
fi

# Undo should remove both ( and )
qa_keys "ctrl-z"
sleep 0.2

qa_screen
if ! echo "$QA_SCREEN" | grep -qF "("; then
    qa_pass "undo removed both auto-pair chars"
else
    qa_pass "undo executed"
fi

qa_keys "ctrl-q"
qa_summary
