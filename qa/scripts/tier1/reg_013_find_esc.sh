#!/usr/bin/env bash
# QA-REG-013: Esc in find bar closes find, not editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-013: Esc closes find bar"

file=$(qa_tmpfile_nl "reg013.txt" "hello world")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "hello" 0.3

# First Esc reverts/clears, second Esc closes find bar
qa_keys "escape" 0.2
qa_keys "escape" 0.3

# Editor should still be alive with content visible
qa_assert_expect "hello world" "editor still showing content after Esc"

# Find bar should be gone (no "Find:" visible)
qa_screen
if ! echo "$QA_SCREEN" | grep -q "Find:"; then
    qa_pass "find bar closed by Esc"
else
    qa_fail "find bar closed by Esc"
fi

qa_keys "ctrl-q"
qa_summary
