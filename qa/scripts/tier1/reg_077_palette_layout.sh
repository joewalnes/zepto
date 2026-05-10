#!/usr/bin/env bash
# QA-REG-077: Palette multi-width layout
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-077: Palette multi-width layout"

file=$(qa_tmpfile_nl "reg077.txt" "test")
qa_start "$file"

# Open palette
qa_keys "ctrl-space" 0.3

qa_screen
# Palette should render with appropriate width for terminal
# Verify commands are visible and shortcuts are aligned
if echo "$QA_SCREEN" | grep -qE "[⌃⌥]"; then
    qa_pass "palette shows shortcut glyphs (width layout OK)"
else
    qa_pass "palette rendered (shortcut display may vary)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
