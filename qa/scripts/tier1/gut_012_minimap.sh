#!/usr/bin/env bash
# QA-GUT-012: Alt+M toggles minimap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GUT-012: Minimap toggle"

content=""
for i in $(seq 1 30); do content+="line $i with some content"$'\n'; done
file=$(qa_tmpfile_nl "gut012.txt" "$content")
qa_start "$file"

# Check minimap state via palette. Wait for the palette entry to render
# (fixed sleeps flaked under full-suite parallel load).
qa_keys "ctrl-space"
qa_send "minimap" 0.2
qa_wait_screen '\[(on|off)\]' || true
initial_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Toggle minimap
qa_keys "alt-m"
sleep 0.3

# Check new state — wait for the OPPOSITE state to render so we never
# capture a stale pre-toggle frame
expected_new='\[(on|off)\]'
if [[ "$initial_state" == "[on]" ]]; then expected_new='\[off\]'; fi
if [[ "$initial_state" == "[off]" ]]; then expected_new='\[on\]'; fi
qa_keys "ctrl-space"
qa_send "minimap" 0.2
qa_wait_screen "$expected_new" || true
new_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial_state" && -n "$new_state" && "$initial_state" != "$new_state" ]]; then
    qa_pass "alt-m toggled minimap ($initial_state → $new_state)"
else
    qa_fail "alt-m toggled minimap (before=$initial_state after=$new_state)"
fi

# Toggle back
qa_keys "alt-m"

qa_keys "ctrl-q"
qa_summary
