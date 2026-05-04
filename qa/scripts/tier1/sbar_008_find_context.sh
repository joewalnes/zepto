#!/usr/bin/env bash
# QA-SBAR-008: Find mode changes status bar content
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-008: Status bar in find mode"

file=$(qa_tmpfile_nl "sbar008.txt" "hello world
foo bar")
qa_start "$file"

# Capture normal status bar
qa_screen
normal_last=$(echo "$QA_SCREEN" | tail -2)

# Open find
qa_keys "ctrl-f"
qa_send "hello" 0.3

# Status bar / find bar should show find-related info
qa_screen
find_screen=$(echo "$QA_SCREEN" | tail -5)

if echo "$find_screen" | grep -qE "Esc|Find|Aa|match|1 of"; then
    qa_pass "find mode shows find-related status"
else
    qa_fail "find mode shows find-related status"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
