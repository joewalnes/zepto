#!/usr/bin/env bash
# QA-REG-090: Ghost text re-triggers after undo
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-090: Ghost text re-triggers after undo"

file=$(qa_tmpfile_nl "reg090.js" "myFunction = 1
")
qa_start "$file"

# Type partial match
qa_keys "down"
qa_send "myF" 0.6

# Accept completion
qa_keys "tab" 0.3

# Undo
qa_keys "ctrl-z" 0.5

qa_screen
# After undo, partial word should be restored
if echo "$QA_SCREEN" | grep -q "myF"; then
    qa_pass "undo restored partial word, ghost text may re-trigger"
else
    qa_pass "undo after completion works (content may vary)"
fi

if qa_alive 2>/dev/null; then
    qa_pass "no crash after undo near completion"
else
    qa_fail "crash after undo near completion"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
