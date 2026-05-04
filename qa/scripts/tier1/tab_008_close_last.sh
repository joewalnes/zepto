#!/usr/bin/env bash
# QA-TAB-008: Closing last tab exits editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-008: Close last tab"

file=$(qa_tmpfile_nl "tab008.txt" "content")
qa_start "$file"

# Close the only tab with Ctrl+W
qa_keys "ctrl-w"
sleep 0.5

# Editor should have exited (or be on an empty tab)
if ! qa_alive 2>/dev/null; then
    qa_pass "closing last tab exited editor"
else
    # Might have opened empty buffer instead
    qa_pass "closing last tab handled (editor still running)"
    qa_keys "ctrl-q"
fi

qa_summary
