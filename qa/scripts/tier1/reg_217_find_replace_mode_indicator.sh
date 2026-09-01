#!/usr/bin/env bash
# QA-REG-217: Find bar shows which replace mode is active
#
# bugs.md P2 "No on-screen indicator for Replace-One vs. Replace-All mode,
# and no palette command to switch between them" -- found while fixing the
# P0 find/replace preview bug (QA-REG-211). Renderer.pm's _render_find_bar
# read $find->{replace_all} into a local variable but never used it
# anywhere: the "Replace:" label looked identical in both modes, and the
# only way to switch (Shift+Tab) gave zero visual feedback that anything
# had changed, or that a toggle even existed.
#
# Fix: the "Replace:" label now reads "Rep All:" or "Rep One:" depending
# on find_replace_all, colored like the regex/case toggle pills' active
# (colored) vs. inactive (dim) states. Both strings are exactly 8
# characters -- the same width as the original "Replace:" -- which
# matters: a separate pill widget was tried first and had to be reverted
# after it broke tests/renderer.t's P0 overflow-guard tests. This find bar
# already shrinks its input fields to their floor at common widths
# (76-90 cols) with zero spare margin, so any extra fixed-width element
# overflows there; see bugs.md's FIXED writeup for the measured numbers.
# Also added CommandRegistry.pm's "Replace All Mode" toggle command for a
# second, unambiguous way to discover and flip the mode (Shift+Tab is
# still there, but its second press also cycles regex/case -- confusing
# on its own, which is part of why this bug was filed).
#
# Mouse-click-to-toggle (Editor.pm's handle_find_bar_click, new
# $label_start/$label_end region) is covered by tests/find.t's exact
# click-region-math unit test, not exercised here -- raw SGR mouse click
# injection was confirmed NOT to reach the find bar's click handlers at
# all in this hangon/tmux harness (verified against the pre-existing,
# long-working Esc-pill click too, so this is an environment limitation,
# not a regression), consistent with no other QA script in this repo
# testing find-bar mouse clicks interactively.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-217: Find bar replace-mode indicator"

line_width() {
    printf '%s' "$1" | perl -CSD -pe 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\x1b\[\?[0-9]+[hl]//g; chomp; $_ = length($_)."\n"'
}

file=$(qa_tmpfile_nl "reg215.txt" "aaa bbb aaa
ccc aaa ddd")
qa_start "$file"

# --- Default mode: Replace All -------------------------------------------
qa_keys "ctrl-f"
qa_send "aaa" 0.3
qa_keys "tab"
sleep 0.3

qa_assert_screen "Rep All:" "default mode label reads 'Rep All:'"
qa_assert_not_screen "Rep One:" "default mode label does not also read 'Rep One:'"
qa_assert_not_screen "^ *Find:.*Replace:" "old mode-less 'Replace:' label is gone"

# --- Shift+Tab toggles to Replace One, with visible feedback -------------
# Not in hangon's named `keys` list -- raw CSI injection is the
# established technique (see find_010_replace_single.sh's header note).
printf '\x1b[Z' | qa_raw_stdin

qa_assert_screen "Rep One:" "after Shift+Tab, label reads 'Rep One:'"
qa_assert_not_screen "Rep All:" "after Shift+Tab, label no longer reads 'Rep All:'"

# --- Command palette: "Replace All Mode" toggles it back, with [on]/[off] -
# NOTE: intentionally never escapes OUT of the palette here (only ever
# runs the command via Enter) -- discovered while writing this script
# that opening the palette from find mode and then pressing Escape drops
# back to plain editing instead of restoring the find bar (a separate,
# pre-existing minor quirk, logged in bugs.md, out of scope for this fix).
# Ending each palette interaction with Enter keeps find mode active for
# the width checks below, and each command run is itself the observation.
qa_keys "ctrl-space"
qa_send "Replace All Mode" 0.3
qa_assert_screen "Replace All Mode.*\[off\]" "palette shows [off] while in Replace One mode"
qa_keys "enter"
sleep 0.3

qa_assert_screen "Rep All:" "palette command toggled label back to 'Rep All:'"

qa_keys "ctrl-space"
qa_send "Replace All Mode" 0.3
qa_assert_screen "Replace All Mode.*\[on\]" "palette shows [on] while in Replace All mode"
qa_keys "enter"
sleep 0.3

qa_assert_screen "Rep One:" "palette command toggled label to 'Rep One:' again"

# --- No overflow at the common 80-col default -----------------------------
qa_screen
last_line=$(echo "$QA_SCREEN" | tail -1)
w=$(line_width "$last_line")
if [[ "$w" -le 80 ]]; then
    qa_pass "find bar with mode label fits at 80 cols (width=$w)"
else
    qa_fail "find bar with mode label fits at 80 cols" "width=$w > 80: [$last_line]"
fi

# --- No overflow at a narrower 76-col terminal (the tightest width the
# P0 overflow-guard tests require to pass) --------------------------------
qa_resize_window 76 20
sleep 0.3
qa_screen
last_line=$(echo "$QA_SCREEN" | tail -1)
w=$(line_width "$last_line")
if [[ "$w" -le 76 ]]; then
    qa_pass "find bar with mode label fits at 76 cols (width=$w)"
else
    qa_fail "find bar with mode label fits at 76 cols" "width=$w > 76: [$last_line]"
fi
qa_assert_screen "Rep One:" "mode label still visible (not silently dropped) at 76 cols"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
