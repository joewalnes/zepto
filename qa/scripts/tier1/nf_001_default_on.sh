#!/usr/bin/env bash
# QA-NF-001: Nerd font has a default state and is toggleable
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NF-001: Nerd font default state"

file=$(qa_tmpfile_nl "nf001.txt" "hello")
qa_start "$file"

# Check nerd font state via palette
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$state" == "[on]" || "$state" == "[off]" ]]; then
    qa_pass "nerd font has valid default state ($state)"
else
    qa_fail "nerd font has valid default state (got: $state)"
fi

qa_keys "ctrl-q"
qa_summary
