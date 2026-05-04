#!/usr/bin/env bash
# QA-PRMT-002: Discard changes prompt on quit
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-002: Discard changes"

file=$(qa_tmpfile_nl "prmt002.txt" "original")
qa_start "$file"

# Modify file
qa_send " changed"
sleep 0.2

# Try to quit
qa_keys "ctrl-q"
sleep 0.3

# Should show save/discard prompt
qa_screen
if echo "$QA_SCREEN" | grep -qiE "save|discard|unsaved|modified"; then
    qa_pass "quit shows save/discard prompt"
else
    qa_fail "quit shows save/discard prompt"
fi

# Discard (N)
qa_send "n" 0.3

# Editor should exit
qa_assert_exited "editor exited after discard"
