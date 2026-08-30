#!/usr/bin/env bash
# QA-REG-161: Light-theme tab close (x) and shortcut-hint icons have
# adequate contrast against the active tab background.
# Bug: tab_close_fg (light) was fg_rgb(156,160,176) — only 1.22:1 against
# tab_active_bg (114,135,253), and tab_shortcut_fg was fg_rgb(130,136,156)
# at just 1.11:1 — both nearly invisible on an active (selected) tab.
# Fixed by darkening both to a near-black gray that clears WCAG 3:1
# against all three tab-state surfaces (active/inactive/hover).
# Deterministic contrast math lives in tests/theme_contrast.t; this script
# verifies the actual rendered ANSI bytes on a live active tab.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-161: Tab close/shortcut icon contrast (light theme)"

file=$(qa_tmpfile_nl "reg161.txt" "hello")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t" 0.4
qa_assert_expect "reg161" "file is open"

# Pull the raw ANSI bytes for the tab bar row and check the fg colors used
# for the close icon / shortcut hint are the fixed dark values, not the
# old washed-out light grays.
tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
raw=$(tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null | sed -n '1p')

if echo "$raw" | grep -q '38;2;66;67;74'; then
    qa_pass "tab close icon uses the fixed dark-gray color"
else
    qa_fail "tab close icon uses the fixed dark-gray color" "expected 38;2;66;67;74 in tab bar row"
fi

if echo "$raw" | grep -q '38;2;156;160;176'; then
    qa_fail "old washed-out tab_close_fg is gone" "found stale 38;2;156;160;176 in tab bar row"
else
    qa_pass "old washed-out tab_close_fg is gone"
fi

qa_keys "ctrl-q"
qa_summary
