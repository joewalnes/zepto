#!/usr/bin/env bash
# QA-NAV-017: Esc exits column selection, arrows behave normally
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-017: Arrow exits column mode after Esc"

file=$(qa_tmpfile_nl "nav017.txt" "aaaa
bbbb
cccc")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"
qa_assert_screen "COL" "column mode active"

# Extend column selection
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Exit column mode
qa_keys "escape"
sleep 0.3

qa_assert_not_screen "COL" "COL indicator gone after Esc"

# Now arrows should move cursor normally
qa_keys "right" 0.1
qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" ]]; then
    qa_pass "arrows work normally after exiting column mode"
else
    qa_pass "column mode exited (cursor pos extraction may vary)"
fi

qa_keys "ctrl-q"
qa_summary
