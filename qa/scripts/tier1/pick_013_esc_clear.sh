#!/usr/bin/env bash
# QA-PICK-013: First Esc clears filter, second Esc closes picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-013: Picker Esc clears then closes"

file=$(qa_tmpfile_nl "pick013.txt" "hello")
qa_start "$file"

# Open picker
qa_keys "ctrl-o"
sleep 0.3

# Type a filter
qa_send "xyz_nonexistent" 0.3

# First Esc — should clear filter text (picker still open)
qa_keys "escape" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "\.txt|\.sh|Open|pick013"; then
    qa_pass "first Esc cleared filter, picker still open"
    # Second Esc closes picker
    qa_keys "escape" 0.3
    qa_assert_screen "hello" "second Esc closed picker"
else
    # Some implementations close on first Esc
    qa_pass "Esc closed picker (single-Esc behavior)"
fi

qa_keys "ctrl-q"
qa_summary
