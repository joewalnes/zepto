#!/usr/bin/env bash
# QA-REG-140: Light-theme tab "unsaved" dot has adequate contrast
# Bug: tab_modified_fg (light theme) was a light yellow with ~1.2-1.8:1
# contrast against the tab bar's backgrounds — nearly invisible. Fixed to
# a dark amber that clears WCAG 3:1 against all three tab-state surfaces.
# Deterministic contrast math lives in tests/theme_contrast.t; this script
# verifies the actual rendered ANSI bytes on a live dirty tab.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-140: Tab modified-dot contrast (light theme)"

file=$(qa_tmpfile_nl "reg140.txt" "hello")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t" 0.4

# Dirty the buffer so the modified dot renders
qa_send "z" 0.3

# Pull the raw ANSI bytes for the tab bar row and check the fg color used
# for the dot is the fixed dark-amber value, not the old washed-out one.
tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
raw=$(tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null | sed -n '1p')

if echo "$raw" | grep -q '38;2;95;40;0'; then
    qa_pass "tab modified-dot uses the fixed dark-amber color"
else
    qa_fail "tab modified-dot uses the fixed dark-amber color" "expected 38;2;95;40;0 in tab bar row"
fi

qa_keys "ctrl-z" 0.2
qa_keys "ctrl-q"
qa_summary
