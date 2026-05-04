#!/usr/bin/env bash
# QA-REG-043: Closing middle tab switches to adjacent
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-043: Close middle tab"

f1=$(qa_tmpfile_nl "reg043_a.txt" "AAA")
f2=$(qa_tmpfile_nl "reg043_b.txt" "BBB")
f3=$(qa_tmpfile_nl "reg043_c.txt" "CCC")
qa_start "$f1" "$f2" "$f3"

# Switch to tab 2
qa_keys "alt-."
qa_assert_screen "BBB" "on tab 2"

# Close tab 2 (Ctrl+W saves and closes)
qa_keys "ctrl-w"
sleep 0.3

# Should switch to an adjacent tab (tab 1 or tab 3)
qa_screen
if echo "$QA_SCREEN" | grep -qE "AAA|CCC"; then
    qa_pass "closing middle tab switched to adjacent"
else
    qa_fail "closing middle tab switched to adjacent"
fi

qa_keys "ctrl-q"
qa_summary
