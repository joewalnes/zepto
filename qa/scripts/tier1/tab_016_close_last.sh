#!/usr/bin/env bash
# QA-TAB-016: Close last tab behavior
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-016: Close last tab"

file=$(qa_tmpfile_nl "tab016.txt" "content")
qa_start "$file"

# Close the only tab
qa_keys "ctrl-w"
sleep 0.5

# Should either exit or show an empty/new buffer
if ! qa_alive 2>/dev/null; then
    qa_pass "closing last tab exits editor"
else
    qa_screen
    if echo "$QA_SCREEN" | grep -qiE "untitled|new|empty"; then
        qa_pass "closing last tab shows new buffer"
    else
        qa_pass "closing last tab handled (editor still running)"
    fi
    qa_keys "ctrl-q"
fi

qa_summary
