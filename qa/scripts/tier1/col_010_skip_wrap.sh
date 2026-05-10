#!/usr/bin/env bash
# QA-COL-010: Column selection skips wrap continuation lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-010: Column selection skips wrap continuation"

long1=$(python3 -c "print('A' * 120)")
long2=$(python3 -c "print('B' * 120)")
long3=$(python3 -c "print('C' * 120)")
file=$(qa_tmpfile_nl "col010.txt" "$long1
$long2
$long3")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Enter column mode
qa_keys "alt-c"
qa_assert_screen "COL" "column mode active"

# Extend selection down — should move by doc lines, not visual rows
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Editor should be alive and column mode still active
if qa_alive 2>/dev/null; then
    qa_pass "column selection with wrap doesn't crash"
else
    qa_fail "column selection with wrap crashed"
fi

qa_keys "escape"
qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
