#!/usr/bin/env bash
# QA-CMT-009: Toggle comment preserves indentation
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-009: Comment preserves indent"

file=$(qa_tmpfile_nl "cmt009.py" "def foo():
    x = 1
    y = 2")
qa_start "$file"

# Move to indented line 2
qa_keys "down"

qa_raw $'\x1f'
qa_screen

# Comment should preserve the indentation (e.g. "    # x = 1")
if echo "$QA_SCREEN" | grep -qE "    #|	#"; then
    qa_pass "comment preserves indentation"
else
    qa_fail "comment preserves indentation"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
