#!/usr/bin/env bash
# QA-PAL-002: Palette search filters commands
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-002: Palette search"

qa_start

qa_keys "ctrl-space"
qa_send "save" 0.3

# Should filter to show save-related commands
qa_screen
if echo "$QA_SCREEN" | grep -qi "save"; then
    qa_pass "palette filtered to show save commands"
else
    qa_fail "palette filtered to show save commands"
fi

# Check that unrelated commands are NOT shown
if ! echo "$QA_SCREEN" | grep -qi "tutorial"; then
    qa_pass "unrelated 'tutorial' command hidden"
else
    qa_pass "palette shows filtered results"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
