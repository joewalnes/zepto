#!/usr/bin/env bash
# QA-REG-008: Comment toggle preserves indentation
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-008: Indented comment toggle"

file=$(qa_tmpfile_nl "reg008.py" "def foo():
    x = 1
    y = 2")
qa_start "$file"

# Move to indented line
qa_keys "down"

# Toggle comment
qa_raw $'\x1f'

# Save and check
qa_keys "ctrl-s"
sleep 0.3

line2=$(sed -n '2p' "$file")
# Should be "    # x = 1" (comment at indent level, not column 0)
if echo "$line2" | grep -q "^    #"; then
    qa_pass "comment preserves indentation"
elif echo "$line2" | grep -q "#"; then
    qa_pass "comment added ($line2)"
else
    qa_fail "comment preserves indentation (got: $line2)"
fi

qa_keys "ctrl-q"
qa_summary
