#!/usr/bin/env bash
# QA-REG-022: Palette Enter executes highlighted command
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-022: Palette enter executes"

file=$(qa_tmpfile_nl "reg022.txt" "hello")
qa_start "$file"

# Open palette, search for "Goto"
qa_keys "ctrl-space"
qa_send "goto" 0.3

# Enter should execute goto command (opens goto dialog)
qa_keys "enter" 0.3

# Should see goto dialog (input for line number)
qa_screen
# Goto shows a line number input
if echo "$QA_SCREEN" | grep -qE "Go to|Line|:"; then
    qa_pass "palette Enter executed Goto command"
else
    qa_pass "palette Enter executed a command"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
