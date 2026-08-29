#!/usr/bin/env bash
# QA-REG-139: The "Theme" row's icon reflects the actual current mode
# (auto/dark/light), not a static moon regardless of state.
#
# Found while building P3 "Automatic dark/light mode": CommandRegistry's
# 'toggle_theme' entry had a stale "icon: dynamic: theme_dark or
# theme_light" comment, but nothing anywhere actually swapped the icon —
# it was hardcoded to the moon glyph even in light mode. Fixed in
# Renderer.pm (both the status-bar pill and the palette row) to pick
# theme_auto/theme_dark/theme_light based on the live preference value.
#
# This can't assert exact glyph codepoints portably from a shell script
# (Nerd Font PUA bytes), so it instead asserts the deterministic,
# host-independent part: the icon region BEFORE the "Theme" label differs
# between the dark and light states. Cut at the "Theme" label itself, NOT
# at the "[dark]"/"[light]" bracket text — the palette right-aligns that
# bracket with padding, so a naive cut-before-the-bracket comparison would
# "differ" purely because "dark" and "light" are different lengths (a
# tautological pass unrelated to the icon). Cutting at the fixed "Theme"
# label isolates exactly the icon glyph + border, which is the same
# length regardless of which mode is active.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-139: Theme row icon reflects current mode"

file=$(qa_tmpfile_nl "reg139.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_screen
dark_line=$(echo "$QA_SCREEN" | grep -E 'Theme.*⌃T' | head -1)
dark_prefix="${dark_line%%Theme*}"
qa_keys "escape"
qa_keys "escape"

if [[ -z "$dark_line" ]]; then
    qa_fail "Found the Theme row in dark mode" "No line matched 'Theme.*⌃T'"
else
    qa_pass "Found the Theme row in dark mode"
fi

qa_keys "ctrl-t" 0.4   # -> light

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_screen
light_line=$(echo "$QA_SCREEN" | grep -E 'Theme.*⌃T' | head -1)
light_prefix="${light_line%%Theme*}"
qa_keys "escape"
qa_keys "escape"

if [[ -z "$light_line" ]]; then
    qa_fail "Found the Theme row in light mode" "No line matched 'Theme.*⌃T'"
else
    qa_pass "Found the Theme row in light mode"
fi

if [[ -n "$dark_prefix" && -n "$light_prefix" && "$dark_prefix" != "$light_prefix" ]]; then
    qa_pass "Theme row icon differs between dark and light modes"
else
    qa_fail "Theme row icon differs between dark and light modes" \
        "dark prefix: [$dark_prefix]  light prefix: [$light_prefix]"
fi

qa_keys "ctrl-q"
qa_summary
