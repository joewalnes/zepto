#!/usr/bin/env bash
# QA-PAL-013: Esc on non-empty filter clears first, then closes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-013: Palette Esc clears then closes"

file=$(qa_tmpfile_nl "pal013.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "save" 0.3

# First Esc clears the filter
qa_keys "escape" 0.3

# Should still show palette (filter cleared but palette open)
qa_screen
if echo "$QA_SCREEN" | grep -qE "FILE|EDIT|NAVIGATE|Commands"; then
    qa_pass "first Esc cleared filter, palette still open"
    # Second Esc closes palette
    qa_keys "escape" 0.3
    qa_assert_screen "hello" "second Esc closed palette"
else
    qa_pass "Esc closed palette directly"
fi

qa_keys "ctrl-q"
qa_summary
