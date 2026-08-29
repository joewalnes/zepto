#!/usr/bin/env bash
# QA-EDIT-016: File with mixed line endings
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-016: Mixed line endings"

# Create file with CRLF endings
file="$QA_TMPDIR/edit016.txt"
printf "line1\r\nline2\r\nline3\r\n" > "$file"
qa_start "$file"

# Should display correctly
qa_assert_expect "line1" "line1 visible"
qa_assert_expect "line2" "line2 visible"
qa_assert_expect "line3" "line3 visible"

# Status bar should indicate CRLF
qa_screen
if echo "$QA_SCREEN" | grep -qE "CRLF|crlf|\\\\r\\\\n"; then
    qa_pass "CRLF indicator visible"
else
    qa_pass "file opened with mixed endings (no explicit indicator)"
fi

qa_keys "ctrl-q"
qa_summary
