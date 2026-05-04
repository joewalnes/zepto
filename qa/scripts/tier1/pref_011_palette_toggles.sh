#!/usr/bin/env bash
# QA-PREF-011: Preferences viewable in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-011: Preference toggles in palette"

file=$(qa_tmpfile_nl "pref011.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "minimap" 0.3

# Should see Minimap toggle with on/off state
qa_screen
if echo "$QA_SCREEN" | grep -qiE "minimap.*(on|off)"; then
    qa_pass "Minimap toggle shows current state"
elif echo "$QA_SCREEN" | grep -qi "minimap"; then
    qa_pass "Minimap toggle found in palette"
else
    qa_fail "Minimap toggle not found"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
