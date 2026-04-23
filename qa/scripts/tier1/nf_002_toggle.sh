#!/usr/bin/env bash
# QA-NF-002: Alt+I toggles nerd font
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NF-002: Nerd font toggle"

file=$(qa_tmpfile_nl "nf002.txt" "hello")
qa_start "$file"

qa_screen
before="$QA_SCREEN"

qa_keys "alt-i"
qa_screen
after="$QA_SCREEN"

if [[ "$before" != "$after" ]]; then
    qa_pass "alt-i changed screen rendering"
else
    qa_fail "alt-i changed screen rendering"
fi

# Toggle back
qa_keys "alt-i"

qa_keys "ctrl-q"
qa_summary
