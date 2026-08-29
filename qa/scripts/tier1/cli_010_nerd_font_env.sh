#!/usr/bin/env bash
# QA-CLI-010: ZEPTO_NERD_FONT=0 env var disables glyphs
# NOTE: hangon sessions do NOT inherit the client env — the env var must be
# injected with an `env` wrapper inside the session command (an exported
# var never reaches zepto; this test used to pass only via shared-state
# pollution from other tests).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-010: ZEPTO_NERD_FONT=0 env var"

file=$(qa_tmpfile_nl "cli010.txt" "hello")

hangon start process --name "$QA_SESSION" -- \
    env ZEPTO_NERD_FONT=0 \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$file"
sleep "$QA_RENDER_WAIT"

# Check palette for nerd font state
qa_keys "ctrl-space"
qa_send "nerd" 0.2
qa_wait_screen '\[(on|off)\]' || true
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
