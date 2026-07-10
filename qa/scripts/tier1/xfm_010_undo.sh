#!/usr/bin/env bash
# QA-XFM-010: Transform can be undone
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-010: Transform undo"

file=$(qa_tmpfile_nl "xfm010.txt" "cherry
apple
banana")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

# Verify sort happened (real check: reordering, not mere presence of a word
# that was already in the input — see QA-XFM-001/QA-REG-017 for the same fix)
qa_screen
apple_line=$(echo "$QA_SCREEN" | grep -n "apple" | head -1 | cut -d: -f1 || true)
cherry_line=$(echo "$QA_SCREEN" | grep -n "cherry" | head -1 | cut -d: -f1 || true)
if [[ -n "$apple_line" && -n "$cherry_line" && "$apple_line" -lt "$cherry_line" ]]; then
    qa_pass "sorted content visible (apple before cherry)"
else
    qa_fail "sorted content visible (apple before cherry)" "apple=$apple_line cherry=$cherry_line"
fi

# Undo
qa_keys "ctrl-z"

# Should revert to original order (cherry, apple, banana) — check cherry is
# back on line 1 of the document, not merely present anywhere on screen
# (the file only has 3 lines, so "present in the first 5 screen rows" is
# always true regardless of order and would not catch a broken undo).
qa_screen
cherry_line_after=$(echo "$QA_SCREEN" | grep -n "cherry" | head -1 | cut -d: -f1 || true)
apple_line_after=$(echo "$QA_SCREEN" | grep -n "apple" | head -1 | cut -d: -f1 || true)
if [[ -n "$cherry_line_after" && -n "$apple_line_after" && "$cherry_line_after" -lt "$apple_line_after" ]]; then
    qa_pass "undo reverted transform (cherry before apple again)"
else
    qa_fail "undo reverted transform (cherry before apple again)" \
        "cherry=$cherry_line_after apple=$apple_line_after"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
