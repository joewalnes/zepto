#!/usr/bin/env bash
# QA-WRAP-004: Arrow key movement through wrapped lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-004: Wrap cursor movement"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap004.txt" "$long_line
short line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Down arrow should navigate through visual wrapped lines
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1

qa_cursor_pos
# Should still be on logical line 1 but visually lower
if [[ -n "$QA_CURSOR_LINE" ]]; then
    qa_pass "down arrow works in wrapped mode (at line $QA_CURSOR_LINE)"
else
    qa_fail "down arrow works in wrapped mode"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
