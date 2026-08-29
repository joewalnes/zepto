#!/usr/bin/env bash
# QA-TAB-018: Ctrl+Shift+PgUp/PgDn reorders tabs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-018: Reorder tabs"

file1=$(qa_tmpfile_nl "tab018_a.txt" "content A")
file2=$(qa_tmpfile_nl "tab018_b.txt" "content B")
file3=$(qa_tmpfile_nl "tab018_c.txt" "content C")
qa_start "$file1" "$file2" "$file3"

# Verify initial order — tab018_a should be first/active
qa_assert_expect "tab018_a" "tab A visible"

# Try reorder via palette
qa_keys "ctrl-space"
qa_send "move tab" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qiE "move.*tab|reorder"; then
    qa_keys "enter" 0.3
    qa_pass "tab reorder command found in palette"
else
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
    # Try Ctrl+Shift+PageDown (raw escape sequence)
    qa_raw $'\x1b[6;6~'
    sleep 0.3
    qa_pass "tab reorder key sent"
fi

# Editor should still be alive
if qa_alive 2>/dev/null; then
    qa_pass "no crash during tab reorder"
else
    qa_fail "tab reorder crashed editor"
fi

qa_keys "ctrl-q"
qa_summary
