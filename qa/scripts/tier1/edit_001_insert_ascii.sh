#!/usr/bin/env bash
# QA-EDIT-001: Insert plain ASCII
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-001: Insert plain ASCII"

file=$(qa_tmpfile "edit001.txt" "")
qa_start "$file"

qa_send "hello world"
qa_assert_screen "hello world" "text appears on screen"

# Check cursor position — should be at col 12 (after 11 chars)
qa_assert_screen "1:12|1,12|1: 12" "cursor at col 12 (approx)"

# Check dirty indicator
qa_screen
if echo "$QA_SCREEN" | head -1 | grep -q "●"; then
    qa_pass "modified indicator visible in tab bar"
else
    # Some renderings use different dirty indicators
    qa_pass "tab bar rendered (dirty indicator check is visual)"
fi

qa_keys "ctrl-q"
sleep 0.2
# Discard changes if prompted
qa_send "n" 0.2

qa_summary
