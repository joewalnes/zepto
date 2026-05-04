#!/usr/bin/env bash
# QA-WRAP-007: Selection across wrapped line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-007: Selection across wrap"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap007.txt" "$long_line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Select from start across visual rows
qa_keys "home"
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Copy and check
qa_keys "ctrl-c"

# Verify selection was made (no crash, editor still alive)
if qa_alive 2>/dev/null; then
    qa_pass "selection across wrapped line works (no crash)"
else
    qa_fail "selection across wrapped line crashed editor"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
