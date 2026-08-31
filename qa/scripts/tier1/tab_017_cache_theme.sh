#!/usr/bin/env bash
# QA-TAB-017: Tab bar cache includes theme (REGRESSION)
#
# Bug: Renderer.pm's tab-bar cache key didn't include the theme name, so
# after a theme switch the tab bar kept painting stale colors from the
# previous theme until something else forced a cache miss. Fixed by
# adding $theme->name() to the cache key (Renderer.pm ~line 900).
#
# This script and QA-REG-084 (reg_084_tab_theme_cache.sh) both guard this
# same underlying cache-key bug but through deliberately different paths
# so they don't just duplicate one another:
#   - This script drives the switch via the command palette ("Theme:
#     Dark"/"Theme: Light", deterministic regardless of starting theme)
#     and checks the tab BAR's own background color.
#   - QA-REG-084 drives it via the raw ⌃T toggle key on a single tab and
#     checks the ACTIVE TAB's background color, round-tripping
#     dark->light->dark.
# Together they cover two different entry points and two different
# color properties that both derive from the same cache.
#
# Verifies actual rendered ANSI color bytes (not just "screen changed
# somewhere") via a raw tmux capture-pane, the same technique used in
# QA-REG-140 (reg_140_tab_modified_contrast.sh).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-017: Tab bar cache includes theme"

# Dark tab_bar_bg = bg_rgb(30,32,44); light tab_bar_bg = bg_rgb(230,233,239)
# (lib/Zepto/Theme.pm).
DARK_BAR='48;2;30;32;44'
LIGHT_BAR='48;2;230;233;239'

f1=$(qa_tmpfile_nl "tab017_a.txt" "aaa")
f2=$(qa_tmpfile_nl "tab017_b.txt" "bbb")
qa_start "$f1" "$f2"

tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
capture_row1() {
    tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null | sed -n '1p'
}

# Force a known baseline: dark theme.
qa_keys "ctrl-space"
qa_send "Theme: Dark" 0.3
qa_keys "enter" 0.3
sleep 0.3
raw_dark=$(capture_row1)

if echo "$raw_dark" | grep -qF "$DARK_BAR"; then
    qa_pass "tab bar renders dark theme background (baseline)"
else
    qa_fail "tab bar renders dark theme background (baseline)" "expected $DARK_BAR in tab bar row"
fi

# Switch to light theme.
qa_keys "ctrl-space"
qa_send "Theme: Light" 0.3
qa_keys "enter" 0.3
sleep 0.3
raw_light=$(capture_row1)

if echo "$raw_light" | grep -qF "$LIGHT_BAR" && ! echo "$raw_light" | grep -qF "$DARK_BAR"; then
    qa_pass "tab bar cache updated to light theme background (no stale dark cache)"
else
    qa_fail "tab bar cache updated to light theme background (no stale dark cache)" \
        "expected $LIGHT_BAR and NOT $DARK_BAR in tab bar row after switch"
fi

# Restore dark theme so the persisted preference doesn't leak into other tests.
qa_keys "ctrl-space"
qa_send "Theme: Dark" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
qa_summary
