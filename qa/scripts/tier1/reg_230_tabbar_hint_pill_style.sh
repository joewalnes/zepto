#!/usr/bin/env bash
# QA-REG-230: the tab bar's close/tabs/quit corner hint must render as
# rounded, Title Case pills matching the bottom status bar's visual
# language -- not plain lowercase text -- and must never overflow the
# terminal width at any size, degrading to blank fill (never garbled
# text, never a scrolled/corrupted screen) below its narrow-width floor.
#
# Before this fix: the hint rendered as plain, unstyled lowercase text
# ("^W close   ^Y<-/-> tabs   ^Q quit") directly on the tab bar's own
# background -- no rounded caps, no chip background -- visually nothing
# like the bottom status bar's pills ("Save", "Open File"). Reported by
# the user directly: "buttons at bottom have pill shape, but at top (e.g.
# close, quit) use a different style. Also they're lowercase."
#
# Fix: both the DOCUMENT-context tab bar (Renderer.pm::_render_tab_bar)
# and the FILE_TREE-context hint row's fallback segment now render this
# hint via the same _render_pill_list() helper the status bar's own
# pills use, with Title Case labels ("Close"/"Tabs"/"Quit"). See
# bugs.md "Tab-bar buttons (close/tabs/quit hints)..." for the full
# write-up, including a directly-measured trade-off: real pill chrome
# needs more horizontal room than the old dense plain text, so the
# "never disappears" floor moved from a flat 40 cols to ~44-51 cols
# depending on tab name length -- exhaustively covered by
# tests/renderer.t's synthetic width sweep; this script is the live,
# real-binary confirmation.
#
# NOTE on terminal sizing: `hangon`'s resize mechanism is currently
# broken after a tmux-removal rewrite (see ASKS.md item 4 / bugs.md) --
# qa_resize_window (tmux resize-window) is a documented no-op in this
# environment. This script sets the real pty geometry BEFORE zepto
# starts instead, via `stty cols/rows` inside the launched shell
# (confirmed equivalent to a real terminal starting at that size: the
# child process's own `tput cols`/`tput lines` report the requested
# values), bypassing qa_start's fixed invocation.
# See bugs.md 2026-09-01, qa/21_tabs.txt QA-TAB-013.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-230: Tab bar corner hint renders as Title Case pills, never overflows"

qa_setup

echo "hello" > "$QA_TMPDIR/a.txt"
echo "world" > "$QA_TMPDIR/b.txt"

# --- Check 1: generous width shows the labeled pill form, Title Case ---
hangon start process --name "$QA_SESSION" -- sh -c \
    "stty cols 80 rows 20; exec '$QA_ZEPTO' --state-dir '$QA_STATE_DIR' --no-system-clipboard '$QA_TMPDIR/a.txt' '$QA_TMPDIR/b.txt'"
sleep "$QA_RENDER_WAIT"

qa_screen
top_line=$(echo "$QA_SCREEN" | head -1)

if [[ "$top_line" == *"Close"* && "$top_line" == *"Tabs"* && "$top_line" == *"Quit"* ]]; then
    qa_pass "at 80 cols: corner hint shows Title Case labels (Close/Tabs/Quit)"
else
    qa_fail "at 80 cols: corner hint shows Title Case labels (Close/Tabs/Quit)" "top row: [$top_line]"
fi

if [[ "$top_line" == *"close"* || "$top_line" == *"tabs"* || "$top_line" == *"quit"* ]]; then
    qa_fail "no stale lowercase hint text" "found lowercase close/tabs/quit in: [$top_line]"
else
    qa_pass "no stale lowercase hint text"
fi

qa_stop

# --- Check 2: narrow width degrades gracefully, no scroll corruption ---
# (files were created above; reuse them)
hangon start process --name "$QA_SESSION" -- sh -c \
    "stty cols 40 rows 15; exec '$QA_ZEPTO' --state-dir '$QA_STATE_DIR' --no-system-clipboard '$QA_TMPDIR/a.txt'"
sleep "$QA_RENDER_WAIT"

qa_screen
narrow_top=$(echo "$QA_SCREEN" | head -1)

# The tab bar itself (the untitled/named-tab bracket glyph) must still be
# the first captured line -- if a row elsewhere overflowed $cols, the
# terminal would soft-wrap and scroll the whole screen, pushing the tab
# bar off the top (the QA-REG-179/186 failure class).
if [[ "$narrow_top" == *"a.txt"* ]]; then
    qa_pass "at 40 cols: tab bar (row 1) still visible -- no scroll corruption"
else
    qa_fail "at 40 cols: tab bar (row 1) still visible -- no scroll corruption" "top row: [$narrow_top]"
fi

# Below its floor the hint must degrade to blank fill, not truncated/
# garbled text -- confirm no partial glyph leaks through.
if [[ "$narrow_top" == *"Quit"* || "$narrow_top" == *"quit"* ]]; then
    qa_fail "at 40 cols: hint absent (below its measured floor), not partially rendered" "found quit text in: [$narrow_top]"
else
    qa_pass "at 40 cols: hint absent (below its measured floor), not partially rendered"
fi

qa_keys "ctrl-q" 0.3
qa_stop
qa_summary
