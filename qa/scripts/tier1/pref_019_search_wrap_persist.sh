#!/usr/bin/env bash
# QA-PREF-019: Search Wrap Around toggle discoverable from palette and persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-019: Search Wrap Around persistence"

file=$(qa_tmpfile_nl "pref019.txt" "hello")

qa_start "$file"
qa_keys "ctrl-space"
qa_send "Search Wrap" 0.3
if qa_wait_screen '\[(on|off)\]'; then
    initial=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
    qa_pass "Search Wrap Around toggle discoverable in palette (state: $initial)"
else
    qa_fail "Search Wrap Around toggle not found in palette" "$QA_SCREEN"
    initial=""
fi
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"

qa_restart "$file"
qa_keys "ctrl-space"
qa_send "Search Wrap" 0.3
qa_wait_screen '\[(on|off)\]' >/dev/null || true
after=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial" && -n "$after" && "$initial" != "$after" ]]; then
    qa_pass "Search Wrap Around toggle persisted across restart ($initial -> $after)"
else
    qa_fail "Search Wrap Around toggle did not persist across restart" "initial=$initial after=$after"
fi

qa_keys "ctrl-q"
qa_summary
