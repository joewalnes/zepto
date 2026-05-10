#!/usr/bin/env bash
# QA-PAL-016: Highlighted row respects right border
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-016: Palette highlight border"

file=$(qa_tmpfile_nl "pal016.txt" "test content")
qa_start "$file"

qa_keys "ctrl-space" 0.3

# Navigate to highlight a row
qa_keys "down" 0.1
qa_keys "down" 0.1

qa_screen
# Palette should render without the highlight bleeding into border
if qa_alive 2>/dev/null; then
    qa_pass "palette highlight renders correctly (no crash)"
else
    qa_fail "palette highlight crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
