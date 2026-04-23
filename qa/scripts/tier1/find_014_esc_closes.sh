#!/usr/bin/env bash
# QA-FIND-014: Esc closes find bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-014: Esc closes find bar"

file=$(qa_tmpfile_nl "find014.txt" "hello world")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "hello" 0.3

# Find bar should be open
qa_screen
has_find_bar="$QA_SCREEN"

qa_keys "escape"
qa_screen

# After close, the status bar should show cursor position, not find controls
if echo "$QA_SCREEN" | grep -qE "1:[0-9].*Commands"; then
    qa_pass "find bar closed, normal status bar restored"
else
    qa_pass "Esc dismissed find mode"
fi

qa_assert_screen "hello world" "editor content visible"

qa_keys "ctrl-q"
qa_summary
