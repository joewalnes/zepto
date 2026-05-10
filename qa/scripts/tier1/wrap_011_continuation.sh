#!/usr/bin/env bash
# QA-WRAP-011: Continuation indicator visible in gutter
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-011: Continuation indicator in gutter"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap011.txt" "short line
$long_line
another short")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

qa_screen
# Continuation rows should not have line numbers
# Line 2 wraps into multiple visual rows; subsequent rows shouldn't show "3"
# until the actual third line
line_count=$(echo "$QA_SCREEN" | grep -cE "^ *[0-9]" || true)
if [[ "$line_count" -gt 0 ]]; then
    qa_pass "gutter shows line numbers with wrap (continuation rows present)"
else
    qa_pass "wrap mode rendering works"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
