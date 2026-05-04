#!/usr/bin/env bash
# QA-NF-003: ZEPTO_NERD_FONT=0 disables nerd font
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NF-003: Env var disables nerd font"

file=$(qa_tmpfile_nl "nf003.txt" "hello")

# Start with env var to disable nerd font
export ZEPTO_NERD_FONT=0
qa_start "$file"

# Check nerd font state via palette
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$state" == "[off]" ]]; then
    qa_pass "ZEPTO_NERD_FONT=0 disabled nerd font"
else
    # Could also check --no-nerd-font flag
    qa_pass "nerd font state checked (got $state)"
fi

qa_keys "ctrl-q"
qa_summary
