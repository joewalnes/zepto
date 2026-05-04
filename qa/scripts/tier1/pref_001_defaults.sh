#!/usr/bin/env bash
# QA-PREF-001: Fresh state has expected defaults
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-001: Default preferences"

file=$(qa_tmpfile_nl "pref001.py" "x = 1")
qa_start "$file"

# Check wrap defaults to off for code file
qa_keys "ctrl-space"
qa_send "wrap" 0.3
qa_screen
wrap_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$wrap_state" == "[off]" ]]; then
    qa_pass "wrap defaults to off for .py"
else
    qa_fail "wrap defaults to off for .py (got $wrap_state)"
fi

# Editor alive = no crash with fresh state
if qa_alive 2>/dev/null; then
    qa_pass "editor runs with fresh state dir"
else
    qa_fail "editor runs with fresh state dir"
fi

qa_keys "ctrl-q"
qa_summary
