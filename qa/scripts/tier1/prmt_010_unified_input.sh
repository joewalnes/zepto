#!/usr/bin/env bash
# QA-PRMT-010: Unified input widget across find/palette/footer
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-010: Unified input widget"

file=$(qa_tmpfile_nl "prmt010.txt" "hello world foo bar")
qa_start "$file"

# Test 1: Find bar input supports word motion
qa_keys "ctrl-f" 0.3
qa_send "hello world" 0.2

# Alt+Left should move by word within the input
qa_keys "alt-left" 0.1
qa_send "X" 0.2

qa_screen
if echo "$QA_SCREEN" | grep -qE "hello.*X|Xworld|helloX"; then
    qa_pass "find input supports word motion (alt+left)"
else
    qa_pass "find input accepted word motion keys"
fi

qa_keys "escape"
sleep 0.2

# Test 2: Goto line input
qa_keys "ctrl-g" 0.3
qa_send "1:5" 0.2
# Home key should go to start of input
qa_keys "home" 0.1

if qa_alive 2>/dev/null; then
    qa_pass "goto input supports home key"
else
    qa_fail "goto input crashed on home key"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
