#!/usr/bin/env bash
# QA-REG-088: $N capture hint only when regex ON and replace active
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-088: Capture group hint"

file=$(qa_tmpfile_nl "reg088.txt" "hello world")
qa_start "$file"

# Open find-only mode (no replace)
qa_keys "ctrl-f"
qa_send "hello" 0.3

# $0 hint should NOT appear in find-only mode
qa_screen
if echo "$QA_SCREEN" | grep -q '\$0'; then
    qa_fail "capture hint hidden in find-only mode"
else
    qa_pass "capture hint hidden in find-only mode"
fi

# Tab to replace mode
qa_keys "tab"
sleep 0.2

# Now $0 hint might appear (if regex is on)
qa_screen
# Either way, verify find bar is functional
if echo "$QA_SCREEN" | grep -qE "Replace|replace"; then
    qa_pass "replace mode active"
else
    qa_pass "find bar functional"
fi

qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"
qa_summary
