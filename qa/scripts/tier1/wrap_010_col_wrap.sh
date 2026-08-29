#!/usr/bin/env bash
# QA-WRAP-010: Column selection + word wrap interaction
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-010: Column selection + wrap"

long1=$(python3 -c "print('AAAA ' * 30)")
long2=$(python3 -c "print('BBBB ' * 30)")
long3=$(python3 -c "print('CCCC ' * 30)")
file=$(qa_tmpfile_nl "wrap010.txt" "$long1
$long2
$long3")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Enter column mode
qa_keys "alt-c"
qa_assert_expect "COL" "column mode active"

# Extend column selection
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Should use document columns, not visual rows
if qa_alive 2>/dev/null; then
    qa_pass "column selection works with word wrap (no crash)"
else
    qa_fail "column selection with wrap crashed"
fi

qa_keys "escape"
qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
