#!/usr/bin/env bash
# QA-REG-084: Light mode tab bar updates on theme switch (REGRESSION)
#
# Bug: Renderer.pm's tab-bar cache key didn't include the theme name, so
# the tab bar kept painting stale colors from the previous theme after a
# switch. Fixed by adding $theme->name() to the cache key.
#
# See QA-TAB-017 (tab_017_cache_theme.sh) for the sibling test — both
# guard this same cache-key bug via deliberately different paths so
# they aren't pure duplicates of each other: this one drives the switch
# with the raw ⌃T toggle key (the exact key sequence from the original
# bug report) on a single tab, round-trips dark->light->dark, and checks
# the ACTIVE TAB's background color specifically (QA-TAB-017 uses the
# command palette and checks the tab BAR's own background instead).
#
# Verifies actual rendered ANSI color bytes via a raw tmux capture-pane
# (same technique as QA-REG-140 / reg_140_tab_modified_contrast.sh),
# not just "screen changed somewhere".
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-084: Tab bar cache updates on theme switch"

# Dark tab_active_bg = bg_rgb(52,79,138); light tab_active_bg = bg_rgb(114,135,253)
# (lib/Zepto/Theme.pm).
DARK_ACTIVE='48;2;52;79;138'
LIGHT_ACTIVE='48;2;114;135;253'

file=$(qa_tmpfile_nl "reg084.txt" "test content")
qa_start "$file"

tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
capture_row1() {
    tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null | sed -n '1p'
}

# Force a known baseline: dark theme (⌃T is a relative toggle, so start
# from a deterministic state via the palette before exercising the key).
qa_keys "ctrl-space"
qa_send "Theme: Dark" 0.3
qa_keys "enter" 0.3
sleep 0.3
raw_dark=$(capture_row1)

if echo "$raw_dark" | grep -qF "$DARK_ACTIVE"; then
    qa_pass "active tab renders dark theme background (baseline)"
else
    qa_fail "active tab renders dark theme background (baseline)" "expected $DARK_ACTIVE in tab bar row"
fi

# Toggle to light with the raw key (the original bug's exact trigger).
qa_keys "ctrl-t"
sleep 0.3
raw_light=$(capture_row1)

if echo "$raw_light" | grep -qF "$LIGHT_ACTIVE" && ! echo "$raw_light" | grep -qF "$DARK_ACTIVE"; then
    qa_pass "active tab cache updated to light theme background on ctrl-t (no stale dark cache)"
else
    qa_fail "active tab cache updated to light theme background on ctrl-t (no stale dark cache)" \
        "expected $LIGHT_ACTIVE and NOT $DARK_ACTIVE in tab bar row after ctrl-t"
fi

# Toggle back to dark — round-trip must also update cleanly, not crash.
qa_keys "ctrl-t"
sleep 0.3
raw_back=$(capture_row1)

if qa_alive 2>/dev/null; then
    qa_pass "double theme toggle does not crash"
else
    qa_fail "double theme toggle does not crash" "session died after second ctrl-t"
fi

if echo "$raw_back" | grep -qF "$DARK_ACTIVE" && ! echo "$raw_back" | grep -qF "$LIGHT_ACTIVE"; then
    qa_pass "active tab cache reverts to dark theme background on second ctrl-t"
else
    qa_fail "active tab cache reverts to dark theme background on second ctrl-t" \
        "expected $DARK_ACTIVE and NOT $LIGHT_ACTIVE in tab bar row after second ctrl-t"
fi

qa_keys "ctrl-q"
qa_summary
