#!/usr/bin/env bash
# QA-SBAR-002: Status bar shows file type
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-002: File type indicator"

file=$(qa_tmpfile_nl "sbar002.py" "def hello():
    print('world')")
qa_start "$file"

# Status bar should show Python file type
qa_screen
if echo "$QA_SCREEN" | grep -qiE "python|py"; then
    qa_pass "status bar shows Python file type"
else
    qa_fail "status bar shows Python file type"
fi

qa_keys "ctrl-q"
qa_summary
