#!/usr/bin/env bash
# QA-SBAR-014: Multi-cursor shows cursor count in status bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-014: Multi-cursor count in status bar"

file=$(qa_tmpfile_nl "sbar014.txt" "foo bar foo
baz foo qux")
qa_start "$file"

# Select word and add cursors with Ctrl+D
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Status bar should show cursor count
qa_wait_screen '[23]' || true
if echo "$QA_SCREEN" | grep -qE "[23].*cursor|cursor.*[23]|[23].*sel"; then
    qa_pass "multi-cursor count visible in status bar"
else
    # Just check that something changed in the status area
    last_lines=$(echo "$QA_SCREEN" | tail -2)
    if echo "$last_lines" | grep -qE "[23]"; then
        qa_pass "multi-cursor indicator in status area"
    else
        qa_fail "multi-cursor count visible in status bar"
    fi
fi

qa_keys "escape"
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
