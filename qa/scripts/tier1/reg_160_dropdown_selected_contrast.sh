#!/usr/bin/env bash
# QA-REG-160: Light-theme command-palette selected-item text has adequate
# contrast against its own highlight background.
# Bug: dropdown_selected_fg (light theme) was fg_rgb(239,241,245) — an
# off-white nearly identical in luminance to menu_active_bg's near-twin
# dropdown_selected_bg fg_rgb(114,135,253) lavender highlight, only 2.81:1
# (just under the WCAG 3:1 UI-component minimum). Fixed to pure white
# (255,255,255), matching the same white-on-lavender pattern already used
# elsewhere in this theme (tab_active_fg, status_file_fg, pill_palette_fg).
# Deterministic contrast math lives in tests/theme_contrast.t; this script
# verifies the actual rendered ANSI bytes on a live, selected palette row.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-160: Command palette selected-item contrast (light theme)"

file=$(qa_tmpfile_nl "reg160.txt" "hello")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t" 0.4

# Open the command palette — the first row is selected by default, so its
# text renders with dropdown_selected_fg on dropdown_selected_bg.
qa_keys "ctrl-space" 0.4
qa_assert_expect "Commands" "command palette is open"

# Pull the raw ANSI bytes for the selected row and check the fg color used
# is the fixed pure-white value, not the old washed-out off-white.
tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
raw=$(tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null)

if echo "$raw" | grep -q '38;2;255;255;255'; then
    qa_pass "palette selected-item text uses the fixed pure-white color"
else
    qa_fail "palette selected-item text uses the fixed pure-white color" \
        "expected 38;2;255;255;255 somewhere in the palette rows"
fi

# And make sure the old, nearly-invisible off-white is gone.
if echo "$raw" | grep -q '38;2;239;241;245'; then
    qa_fail "old washed-out dropdown_selected_fg is gone" \
        "found stale 38;2;239;241;245 in output"
else
    qa_pass "old washed-out dropdown_selected_fg is gone"
fi

qa_keys "escape" 0.2
qa_keys "ctrl-q"
qa_summary
