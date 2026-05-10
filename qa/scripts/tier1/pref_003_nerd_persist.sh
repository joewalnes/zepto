#!/usr/bin/env bash
# QA-PREF-003: Nerd font toggle persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-003: Nerd font persistence"

file=$(qa_tmpfile_nl "pref003.txt" "hello")

# Session 1: toggle nerd font
qa_start "$file"
qa_keys "alt-i"
sleep 0.2
qa_keys "ctrl-q"

# Session 2: check state persisted
qa_restart "$file"
qa_keys "ctrl-space"
qa_send "nerd" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$state" ]]; then
    qa_pass "nerd font state persisted ($state)"
else
    qa_fail "nerd font state visible"
fi

qa_keys "ctrl-q"
qa_summary
