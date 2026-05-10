#!/usr/bin/env bash
# QA-COL-009: Mouse drag in column mode creates rectangular selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-009: Mouse drag in column mode"

file=$(qa_tmpfile_nl "col009.txt" "aaaa bbbb cccc
dddd eeee ffff
gggg hhhh iiii")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"
qa_assert_screen "COL" "column mode active"

# Drag in text area
hangon mouse-drag "$QA_SESSION" --from 8,2 --to 12,4 --steps 5
sleep 0.3

qa_screen
# Should still be in column mode with selection
if echo "$QA_SCREEN" | grep -qE "COL"; then
    qa_pass "drag in column mode creates rectangular selection"
else
    qa_fail "column mode lost after drag"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
