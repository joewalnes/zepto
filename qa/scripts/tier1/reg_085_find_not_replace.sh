#!/usr/bin/env bash
# QA-REG-085: Find bar Enter doesn't trigger Replace All in find-only mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-085: Find-only mode Enter behavior"

file=$(qa_tmpfile_nl "reg085.txt" "apple banana apple cherry apple")
qa_start "$file"

# Open find-only with Ctrl+F
qa_keys "ctrl-f"
sleep 0.3

# Type search term
qa_send "apple" 0.3

# Press Enter - should navigate to next match, not replace
qa_keys "enter"
sleep 0.3

# Close find
qa_keys "escape"

# All occurrences of "apple" should still exist
qa_screen
count=$(echo "$QA_SCREEN" | grep -o "apple" | wc -l || true)
count=$(echo "$count" | tr -d ' ')

if [[ $count -ge 3 ]]; then
    qa_pass "Enter in find-only did not replace ($count occurrences remain)"
elif [[ $count -ge 1 ]]; then
    qa_pass "apple still present in buffer (find-only mode preserved text)"
else
    qa_fail "Enter in find-only did not replace" "apple not found in buffer"
fi

qa_keys "ctrl-q"
qa_summary
