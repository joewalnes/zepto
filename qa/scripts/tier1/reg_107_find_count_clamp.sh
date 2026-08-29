#!/usr/bin/env bash
# QA-REG-107: Find match counter clamps when the match count shrinks
# Bug: on match 3 of 3, toggling regex off (matches drop to 1) showed
# "3 of 1" — the current-match index wasn't clamped to the new count.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-107: Find counter clamp"

file=$(qa_tmpfile_nl "reg107.txt" $'fooXbar\nfoo.bar\nfooYbar')
qa_start "$file"

qa_keys "ctrl-f"
qa_send 'foo.bar' 0.4
qa_assert_expect '1 of 1' "literal default matches 1"

# Regex on: 3 matches; navigate to the last one (↑↓ arrows navigate,
# Enter closes the find bar)
qa_keys "ctrl-r" 0.4
qa_assert_expect 'of 3' "regex matches 3"
qa_keys "down" 0.3
qa_keys "down" 0.3
qa_assert_expect '3 of 3' "navigated to match 3 of 3"

# Regex off again: count shrinks to 1 — index must clamp, never "3 of 1"
qa_keys "ctrl-r" 0.4
qa_assert_expect '1 of 1' "counter clamped to 1 of 1 after shrink"
qa_screen
if echo "$QA_SCREEN" | grep -qE '[2-9] of 1'; then
    qa_fail "no out-of-range counter" "screen shows an N-of-1 with N>1"
else
    qa_pass "no out-of-range counter"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
