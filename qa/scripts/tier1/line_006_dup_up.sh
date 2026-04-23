#!/usr/bin/env bash
# QA-LINE-006: Ctrl+U duplicates line above
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-006: Duplicate line up"

file=$(qa_tmpfile_nl "line006.txt" "original line")
qa_start "$file"

qa_keys "ctrl-u"

# Should now have two copies of the line
qa_screen
count=$(echo "$QA_SCREEN" | grep -c "original line" || true)
if [[ $count -ge 2 ]]; then
    qa_pass "line duplicated ($count copies visible)"
else
    qa_fail "line duplicated (only $count copy visible)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
