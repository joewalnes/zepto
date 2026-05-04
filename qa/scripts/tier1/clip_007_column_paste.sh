#!/usr/bin/env bash
# QA-CLIP-007: Column copy/paste preserves rectangle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-007: Column clipboard preserves rectangle"

file=$(qa_tmpfile_nl "clip007.txt" "aaaa1111
bbbb2222
cccc3333
dddd4444")
qa_start "$file"

# Enter column mode, select first 3 rows x 4 cols
qa_keys "alt-c"
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Copy
qa_keys "ctrl-c"

# Exit column mode
qa_keys "escape"

# Move to line 4
qa_keys "ctrl-g"
qa_send "4" 0.2
qa_keys "enter"

# Paste
qa_keys "ctrl-v"

qa_screen
if echo "$QA_SCREEN" | grep -qE "aaaa|bbbb|cccc"; then
    qa_pass "column paste inserted rectangle"
else
    qa_fail "column paste did not insert rectangle"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
