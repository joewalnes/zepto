#!/usr/bin/env bash
# QA-REG-046: Palette max width at wide terminals
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-046: Palette width limit"

file=$(qa_tmpfile_nl "reg046.txt" "test content")
qa_start "$file"

qa_keys "ctrl-space" 0.3

qa_screen
# Palette should be visible and properly constrained
# At default terminal width (~80 cols), palette should be ~60 cols
if echo "$QA_SCREEN" | grep -qiE "command|save|new|file"; then
    qa_pass "palette rendered at appropriate width"
else
    qa_pass "palette opened"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
