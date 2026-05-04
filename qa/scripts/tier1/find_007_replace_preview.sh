#!/usr/bin/env bash
# QA-FIND-007: Replace shows live preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-007: Replace preview"

file=$(qa_tmpfile_nl "find007.txt" "foo bar foo
baz foo")
qa_start "$file"

# Open find and type search
qa_keys "ctrl-f"
qa_send "foo" 0.3

# Tab to replace field
qa_keys "tab"
qa_send "ZZZ" 0.3

# Should see preview of replacement in editor area
qa_screen
if echo "$QA_SCREEN" | grep -q "ZZZ"; then
    qa_pass "replace preview shows ZZZ"
else
    qa_fail "replace preview shows ZZZ"
fi

# Escape should revert the preview (no changes saved)
qa_keys "escape" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "foo"; then
    qa_pass "escape reverted replace preview"
else
    qa_fail "escape reverted replace preview"
fi

qa_keys "ctrl-q"
qa_summary
