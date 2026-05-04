#!/usr/bin/env bash
# QA-NF-004: Nerd font toggle visible in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NF-004: Nerd font in palette"

file=$(qa_tmpfile_nl "nf004.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "nerd" 0.3

qa_assert_screen "[Nn]erd" "nerd font command visible in palette"

qa_screen
if echo "$QA_SCREEN" | grep -qE '\[(on|off)\]'; then
    qa_pass "nerd font toggle shows state indicator"
else
    qa_fail "nerd font toggle shows state indicator"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
