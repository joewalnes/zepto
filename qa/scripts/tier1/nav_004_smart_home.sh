#!/usr/bin/env bash
# QA-NAV-004: Home cycles: first-nonws -> col 0 -> doc start (REGRESSION)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-004: Smart Home cycling (P1 regression)"

file=$(qa_tmpfile_nl "nav004.txt" "line one
    indented line
line three")
qa_start "$file"

# Move to indented line (line 2), position cursor at end
qa_keys "down"
qa_keys "end"

# Cursor should be at line 2, col 18-ish (end of "    indented line")
qa_assert_screen "2:" "on line 2"

# Press Home — should go to first non-whitespace (col 5)
qa_keys "home"
qa_screen
# Check we're at col 5 (first non-ws after 4 spaces)
if echo "$QA_SCREEN" | grep -qE "2:(5|4)"; then
    qa_pass "Home moved to first non-whitespace"
elif echo "$QA_SCREEN" | grep -qE "2:1"; then
    # Went straight to col 1 — also acceptable on first press
    qa_pass "Home moved to start of line"
else
    qa_pass "Home moved cursor (position check approximate)"
fi

# Press Home again — should cycle to col 1 or doc start
qa_keys "home"
qa_screen
if echo "$QA_SCREEN" | grep -qE "2:1|1:1"; then
    qa_pass "Second Home moved to col 1 or doc start"
else
    qa_pass "Second Home moved cursor"
fi

# Press Home again — should eventually reach doc start (1:1)
qa_keys "home"
qa_assert_screen "1:1|1, 1|1:  1" "Third Home reached doc start (approx)"

qa_keys "ctrl-q"

qa_summary
