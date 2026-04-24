#!/usr/bin/env bash
# QA-NF-002: Alt+I toggles nerd font
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NF-002: Nerd font toggle"

file=$(qa_tmpfile_nl "nf002.txt" "hello")
qa_start "$file"

# Check nerd font state via palette
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
initial_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Toggle
qa_keys "alt-i"
sleep 0.3

# Check state changed
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
new_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial_state" && -n "$new_state" && "$initial_state" != "$new_state" ]]; then
    qa_pass "alt-i toggled nerd font ($initial_state → $new_state)"
else
    qa_fail "alt-i toggled nerd font (before=$initial_state after=$new_state)"
fi

# Toggle back
qa_keys "alt-i"

qa_keys "ctrl-q"
qa_summary
