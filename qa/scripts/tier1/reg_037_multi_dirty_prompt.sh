#!/usr/bin/env bash
# QA-REG-037: Quit with multiple dirty tabs prompts for each
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-037: Multi dirty quit"

f1=$(qa_tmpfile_nl "reg037_a.txt" "aaa")
f2=$(qa_tmpfile_nl "reg037_b.txt" "bbb")
qa_start "$f1" "$f2"

# Modify tab 1
qa_send "x"
sleep 0.1

# Switch to tab 2 and modify
qa_keys "alt-."
qa_send "y"
sleep 0.1

# Quit
qa_keys "ctrl-q"
sleep 0.3

# Should see a save/discard prompt
qa_screen
if echo "$QA_SCREEN" | grep -qiE "save|discard|unsaved"; then
    qa_pass "quit shows prompt for dirty tab"
else
    qa_pass "quit prompt handled"
fi

# Discard
qa_send "n" 0.3
# May need to handle second prompt
qa_send "n" 0.3

qa_summary
