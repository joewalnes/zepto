#!/usr/bin/env bash
# QA-REG-051: Prominent save prompt with pill buttons
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-051: Prominent save prompt"

file=$(qa_tmpfile_nl "reg051.txt" "original content")
qa_start "$file"

# Make edit to dirty the buffer
qa_keys "end"
qa_send " modified"

# Try to quit — should show save prompt
qa_keys "ctrl-q"
sleep 0.3

# Should see save/discard/cancel options
qa_screen
has_save=$(echo "$QA_SCREEN" | grep -ciE "save|Save" || true)
has_discard=$(echo "$QA_SCREEN" | grep -ciE "discard|Discard|Don't Save" || true)
has_cancel=$(echo "$QA_SCREEN" | grep -ciE "cancel|Cancel" || true)

if [[ "$has_save" -ge 1 ]]; then
    qa_pass "save prompt shows Save option"
else
    qa_fail "save prompt shows Save option"
fi

if [[ "$has_discard" -ge 1 || "$has_cancel" -ge 1 ]]; then
    qa_pass "save prompt shows Discard/Cancel options"
else
    qa_fail "save prompt shows Discard/Cancel options"
fi

# Dismiss by discarding
qa_send "n"
sleep 0.3

qa_summary
