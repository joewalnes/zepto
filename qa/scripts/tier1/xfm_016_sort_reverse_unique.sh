#!/usr/bin/env bash
# QA-XFM-016: Sort Lines / Reverse Lines / Unique Lines (built-in,
# whole-document scope since nothing is selected).
#
# "home" is pressed before each ⌃Space: ⌃Space is context-sensitive and
# routes to word-completion instead of the palette if the cursor sits
# immediately after a word character (see QA-XFM-015 NOTES).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-016: Sort / Reverse / Unique Lines"

file=$(qa_tmpfile_nl "xfm016.txt" "banana
apple
cherry
apple")
qa_start "$file"

# --- Sort Lines ---
qa_keys "home" 0.2
qa_keys "ctrl-space"
qa_send "Sort Lines" 0.3
qa_keys "enter" 0.3

qa_screen
seq=$(echo "$QA_SCREEN" | grep -oE '(banana|apple|cherry)' | tr '\n' ',')
if [[ "$seq" == "apple,apple,banana,cherry," ]]; then
    qa_pass "Sort Lines sorts alphabetically"
else
    qa_fail "Sort Lines sorts alphabetically" "got order: $seq"
fi

qa_keys "ctrl-z" 0.3

# --- Unique Lines (preserves first-occurrence order, unlike sort -u) ---
qa_keys "home" 0.2
qa_keys "ctrl-space"
qa_send "Unique Lines" 0.3
qa_keys "enter" 0.3

qa_screen
seq=$(echo "$QA_SCREEN" | grep -oE '(banana|apple|cherry)' | tr '\n' ',')
if [[ "$seq" == "banana,apple,cherry," ]]; then
    qa_pass "Unique Lines removes the duplicate, preserving original order"
else
    qa_fail "Unique Lines removes the duplicate, preserving original order" "got order: $seq"
fi

qa_keys "ctrl-z" 0.3

# --- Reverse Lines ---
qa_keys "home" 0.2
qa_keys "ctrl-space"
qa_send "Reverse Lines" 0.3
qa_keys "enter" 0.3

qa_screen
seq=$(echo "$QA_SCREEN" | grep -oE '(banana|apple|cherry)' | tr '\n' ',')
if [[ "$seq" == "apple,cherry,apple,banana," ]]; then
    qa_pass "Reverse Lines reverses line order"
else
    qa_fail "Reverse Lines reverses line order" "got order: $seq"
fi

qa_keys "ctrl-z" 0.3
qa_screen
seq=$(echo "$QA_SCREEN" | grep -oE '(banana|apple|cherry)' | tr '\n' ',')
if [[ "$seq" == "banana,apple,cherry,apple," ]]; then
    qa_pass "undo restores the original 4-line order"
else
    qa_fail "undo restores the original 4-line order" "got order: $seq"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
