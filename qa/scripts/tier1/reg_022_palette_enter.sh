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
# Goto shows a line number input
qa_assert_expect "Go to|Line|:" "palette Enter executed Goto command"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
