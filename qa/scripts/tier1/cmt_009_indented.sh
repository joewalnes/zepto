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

# Comment should preserve the indentation (e.g. "    # x = 1")
qa_assert_expect "    #|	#" "comment preserves indentation"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
