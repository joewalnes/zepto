#!/usr/bin/env bash
# QA-REG-042: Find/replace pills clickable
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-042: Find bar pills clickable"

file=$(qa_tmpfile_nl "reg042.txt" "hello world test 123 stuff")
qa_start "$file"

# Open find
qa_keys "ctrl-f"
qa_send "hello" 0.3

# Find the status bar with pills (last 2 lines)
qa_wait_screen 'Esc|Enter' || true
total_lines=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')
status_row=$total_lines

# Click on the regex pill area (.* is usually near left of status bar)
# Status bar pills: .* ⌃R, Aa ⌃C, ✗ Esc, ✓ Enter
# Try clicking on the Aa pill to toggle case
hangon mouse-click "$QA_SESSION" --x 15 --y "$status_row"
sleep 0.3

# Editor should still be responsive
if qa_alive; then
    qa_pass "clicking find bar pill handled"
else
    qa_fail "clicking find bar pill handled" "editor crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
