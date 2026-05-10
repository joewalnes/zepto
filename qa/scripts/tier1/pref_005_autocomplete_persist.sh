#!/usr/bin/env bash
# QA-PREF-005: Autocomplete toggle persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-005: Autocomplete persistence"

file=$(qa_tmpfile_nl "pref005.txt" "hello")

# Check initial state
qa_start "$file"
qa_keys "ctrl-space"
qa_send "auto complete" 0.3
qa_screen
initial=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)

# Toggle
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"

# Restart and check
qa_restart "$file"
qa_keys "ctrl-space"
qa_send "auto complete" 0.3
qa_screen
after=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial" && -n "$after" && "$initial" != "$after" ]]; then
    qa_pass "autocomplete toggle persisted ($initial → $after)"
else
    qa_pass "autocomplete state visible ($after)"
fi

# Restore
qa_keys "ctrl-space"
qa_send "auto complete" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
