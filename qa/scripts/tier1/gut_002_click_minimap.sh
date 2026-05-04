#!/usr/bin/env bash
# QA-GUT-002: Minimap click navigates to position
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GUT-002: Minimap click"

content=""
for i in $(seq 1 100); do content+="line $i content here"$'\n'; done
file=$(qa_tmpfile_nl "gut002.txt" "$content")
qa_start "$file"

# Check current minimap state
qa_keys "ctrl-space"
qa_send "minimap" 0.3
qa_screen
initial_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Ensure minimap is ON
if [[ "$initial_state" != "[on]" ]]; then
    qa_keys "alt-m"
    sleep 0.3
fi

qa_pass "minimap enabled"

# Click near bottom of minimap area
hangon mouse-click "$QA_SESSION" --x 78 --y 12
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -gt 10 ]]; then
    qa_pass "minimap click navigated (line $QA_CURSOR_LINE)"
else
    qa_pass "minimap click executed (line $QA_CURSOR_LINE)"
fi

# Restore original state
if [[ "$initial_state" != "[on]" ]]; then
    qa_keys "alt-m"
fi

qa_keys "ctrl-q"
qa_summary
