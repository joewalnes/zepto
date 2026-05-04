#!/usr/bin/env bash
# QA-CLI-010: ZEPTO_NERD_FONT=0 env var disables glyphs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-010: ZEPTO_NERD_FONT=0 env var"

file=$(qa_tmpfile_nl "cli010.txt" "hello")

# Start with nerd font disabled via env var
export ZEPTO_NERD_FONT=0
qa_start "$file"

# Check palette for nerd font state
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$state" == "[off]" ]]; then
    qa_pass "ZEPTO_NERD_FONT=0 disabled nerd font"
else
    qa_fail "ZEPTO_NERD_FONT=0 disabled nerd font (state=$state)"
fi

qa_keys "ctrl-q"
qa_summary
