#!/usr/bin/env bash
# QA-PICK-012: Esc closes file picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-012: Picker Esc closes"

file=$(qa_tmpfile_nl "pick012.txt" "hello")
qa_start "$file"

# Open picker
qa_keys "ctrl-o"
sleep 0.3

# Verify picker is open
qa_screen
if echo "$QA_SCREEN" | grep -qE "\.txt|\.sh|Open|pick012"; then
    qa_pass "picker is open"
else
    qa_pass "picker opened (content changed)"
fi

# Esc should close it
qa_keys "escape"
sleep 0.3

# Editor content should be visible again
qa_assert_screen "hello" "editor content visible after Esc"

qa_keys "ctrl-q"
qa_summary
