#!/usr/bin/env bash
# QA-REG-100: Status bar Commands label prominence
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-100: Commands label prominence"

file=$(qa_tmpfile_nl "reg100.txt" "hello")
qa_start "$file"

qa_assert_screen "Commands" "Commands pill visible on status bar"

# Click Ctrl+Space to verify it works
qa_keys "ctrl-space"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qiE "FILE|EDIT|NAVIGATE|VIEW|Save|Open|Find"; then
    qa_pass "Ctrl+Space opens command palette"
else
    qa_fail "Ctrl+Space opens command palette"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
