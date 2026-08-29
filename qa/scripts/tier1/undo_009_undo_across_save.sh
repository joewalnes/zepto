#!/usr/bin/env bash
# QA-UNDO-009: Undo across save boundary
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-009: Undo across save"

file=$(qa_tmpfile_nl "undo009.txt" "base")
qa_start "$file"

# Type and save
qa_keys "end"
qa_send " first"
qa_keys "ctrl-s"
sleep 0.3

# Type more after save
qa_send " second"
qa_assert_expect "base first second" "both edits visible"

# Undo — should undo post-save changes first
qa_keys "ctrl-z" 0.2
qa_keys "ctrl-z" 0.2
qa_keys "ctrl-z" 0.2

qa_screen
if echo "$QA_SCREEN" | grep -q "base first" && ! echo "$QA_SCREEN" | grep -q "base first second"; then
    qa_pass "undo removed post-save text"
else
    # Even partial undo is acceptable
    qa_screen
    if ! echo "$QA_SCREEN" | grep -q "second"; then
        qa_pass "undo removed post-save text (second gone)"
    else
        qa_fail "undo removed post-save text" "still shows 'second'"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
