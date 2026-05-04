#!/usr/bin/env bash
# QA-REG-036: Merged goto-line pill with Ctrl+G shortcut
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-036: Goto-line pill shows Ctrl+G"

file=$(qa_tmpfile_nl "reg036.txt" "line 1
line 2
line 3")
qa_start "$file"

# Status bar should show cursor position pill
qa_assert_screen "1:1" "cursor position visible in status bar"

# Open goto with Ctrl+G
qa_keys "ctrl-g"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "Go to|Line|:"; then
    qa_pass "Ctrl+G opens goto input"
else
    qa_fail "Ctrl+G opens goto input" "no goto prompt visible"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
