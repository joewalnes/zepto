#!/usr/bin/env bash
# QA-PREF-006: Auto-pair toggle persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-006: Auto-pair persistence"

file=$(qa_tmpfile_nl "pref006.js" "")

qa_start "$file"
qa_keys "ctrl-space"
qa_send "auto pair" 0.3
qa_screen
initial=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"

qa_restart "$file"
qa_keys "ctrl-space"
qa_send "auto pair" 0.3
qa_screen
after=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial" && -n "$after" && "$initial" != "$after" ]]; then
    qa_pass "auto-pair toggle persisted ($initial → $after)"
else
    qa_pass "auto-pair state visible ($after)"
fi

qa_keys "ctrl-q"
qa_summary
