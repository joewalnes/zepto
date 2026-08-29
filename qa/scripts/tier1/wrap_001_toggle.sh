#!/usr/bin/env bash
# QA-WRAP-001: Alt+Z toggles word wrap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-001: Word wrap toggle"

# Create file with a very long line
long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap001.txt" "$long_line")
qa_start "$file"

# Check wrap state via palette. Query the full label ("Word Wrap"), not the
# bare substring "wrap" — that now also fuzzy-matches "Search Wrap Around"
# (QA-PREF-019) and would grab the wrong toggle's on/off state.
qa_keys "ctrl-space"
qa_send "Word Wrap" 0.3
qa_screen
initial_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Toggle wrap
qa_keys "alt-z"
sleep 0.3

# Check new state
qa_keys "ctrl-space"
qa_send "Word Wrap" 0.3
qa_screen
new_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$initial_state" && -n "$new_state" && "$initial_state" != "$new_state" ]]; then
    qa_pass "alt-z toggled wrap ($initial_state → $new_state)"
else
    qa_fail "alt-z toggled wrap (before=$initial_state after=$new_state)"
fi

# Toggle back
qa_keys "alt-z"

qa_keys "ctrl-q"
qa_summary
