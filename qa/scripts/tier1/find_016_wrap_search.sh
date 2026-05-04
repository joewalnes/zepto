#!/usr/bin/env bash
# QA-FIND-016: Find wraps around end of document
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-016: Find wraps around"

file=$(qa_tmpfile_nl "find016.txt" "MARKER_TOP
line two
line three
line four")
qa_start "$file"

# Jump to end of file
qa_keys "ctrl-g"
qa_send "4" 0.2
qa_keys "enter"

# Open find and search for MARKER_TOP
qa_keys "ctrl-f"
qa_send "MARKER_TOP" 0.3

# Should find it (wrapping from bottom to top)
qa_screen
match=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ -n "$match" ]]; then
    qa_pass "find wraps around to match ($match)"
else
    qa_fail "find wraps around to match"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
