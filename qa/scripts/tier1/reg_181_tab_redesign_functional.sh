#!/usr/bin/env bash
# QA-REG-181: The tab bar redesign (solid-fill pills, full-block caps,
# boosted inactive/hover contrast — see bugs.md "Tab bar visual redesign
# (2026-08-30)") did not silently break any of the functional elements it
# was explicitly required to preserve: the dirty-dot indicator, ⌥N
# shortcuts, and mouse click-to-switch on an inactive tab's body.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-181: Tab redesign preserves dirty dot + click-to-switch"

file1=$(qa_tmpfile_nl "reg181_a.txt" "content of file A")
file2=$(qa_tmpfile_nl "reg181_b.txt" "content of file B")
qa_start "$file1" "$file2"
qa_assert_expect "reg181_a" "tab bar visible with two tabs"

# Dirty an inactive tab is impossible without switching to it first, so:
# make tab A dirty while active, then switch to B and confirm A's dot
# persists while inactive (dirty state must render regardless of active
# state, and the redesign's fill-color change must not have hidden it).
qa_send "!"
sleep 0.2
qa_assert_screen "●" "Dirty-dot indicator visible after editing the active tab"

qa_keys "alt-."
sleep 0.3
qa_assert_expect "content of file B" "switched to tab B via keyboard"
qa_assert_screen "●" "Dirty dot still visible on tab A now that it's inactive"

# Click on tab A's body (not its close button) to switch back — this
# exercises the same button-hit-testing the redesign's cap-glyph width
# change could have shifted. Tab A is the first tab, so its body sits a
# few columns in from the left edge of the bar.
hangon mouse-click "$QA_SESSION" --x 6 --y 1
sleep 0.3
qa_assert_expect "content of file A" "clicking tab A's body switched back to it"

# Close tab B via ⌃W (keyboard close). This exercises the exact same
# cmd_close_tab() path a click on the × button would (see
# Editor.pm::handle_tab_bar_click's 'close' case) — the mouse-driven
# close-button hit test itself (computing its exact column from the
# redesigned cap-glyph width and clicking it) is covered separately in
# QA-REG-182, which also covers overflow/scroll.
qa_keys "alt-."
sleep 0.2
qa_assert_expect "content of file B" "switched to tab B to close it"
qa_keys "ctrl-w"
sleep 0.3
qa_assert_not_screen "reg181_b" "Tab B closed and no longer in the tab bar"
qa_assert_expect "content of file A" "closing B left A open and active"

qa_keys "ctrl-q"
qa_summary
