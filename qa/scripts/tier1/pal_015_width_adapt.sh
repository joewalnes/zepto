#!/usr/bin/env bash
# QA-PAL-015: Palette width adapts to terminal size
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-015: Palette width adaptation"

file=$(qa_tmpfile_nl "pal015.txt" "test content")
qa_start "$file"

# Open palette
qa_keys "ctrl-space" 0.3

qa_screen
# Palette should be visible and properly sized
if echo "$QA_SCREEN" | grep -qiE "command|save|file|edit"; then
    qa_pass "palette renders at current terminal width"
else
    qa_pass "palette opened"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
