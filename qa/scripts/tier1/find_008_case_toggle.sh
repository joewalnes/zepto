#!/usr/bin/env bash
# QA-FIND-008: Case sensitivity toggle in find bar (Ctrl+C)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-008: Case sensitivity toggle"

file=$(qa_tmpfile_nl "find008.txt" "Hello hello HELLO
world World WORLD")
qa_start "$file"

# Open find
qa_keys "ctrl-f"
qa_send "hello"

# Default is case-insensitive — should find all 3
qa_wait_screen '[0-9]+ of [0-9]+' || true
match_count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1)

# Toggle case sensitivity with Ctrl+C (shown as Aa ⌃C in find bar)
qa_keys "ctrl-c"

qa_wait_screen '[0-9]+ of [0-9]+' || true
new_count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1)

# Case-sensitive "hello" should match only 1 (lowercase)
if [[ -n "$new_count" && "$new_count" == *"of 1"* ]]; then
    qa_pass "case-sensitive search found only 1 match ($new_count)"
elif [[ -n "$match_count" && -n "$new_count" && "$match_count" != "$new_count" ]]; then
    qa_pass "case toggle changed match count ($match_count → $new_count)"
else
    qa_fail "case toggle changed match count (before=$match_count after=$new_count)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
