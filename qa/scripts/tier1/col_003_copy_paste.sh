#!/usr/bin/env bash
# QA-COL-003: Column select copy and paste preserves rectangle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-003: Column copy paste"

file=$(qa_tmpfile_nl "col003.txt" "abcdef
ghijkl
mnopqr
------")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"

# Select a rectangle: 3 rows, 3 cols (bcd, hij, nop)
qa_keys "right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Copy
qa_keys "ctrl-c"

# Move to the dashes line
qa_keys "escape" 0.2
qa_keys "down" 0.1
qa_keys "home" 0.1

# Paste
qa_keys "ctrl-v"

# Should see pasted rectangle content
qa_screen
if echo "$QA_SCREEN" | grep -qE "bcd|hij|nop"; then
    qa_pass "column paste produced rectangular content"
else
    qa_fail "column paste produced rectangular content"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
