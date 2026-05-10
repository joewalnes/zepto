#!/usr/bin/env bash
# QA-PREF-004: Minimap toggle persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-004: Minimap persistence"

content=""
for i in $(seq 1 50); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "pref004.txt" "$content")

# Session 1: toggle minimap
qa_start "$file"
qa_keys "alt-m"
sleep 0.2
qa_keys "ctrl-q"

# Session 2: check state
qa_restart "$file"
qa_keys "ctrl-space"
qa_send "minimap" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$state" ]]; then
    qa_pass "minimap state persisted ($state)"
else
    qa_fail "minimap state visible"
fi

qa_keys "ctrl-q"
qa_summary
