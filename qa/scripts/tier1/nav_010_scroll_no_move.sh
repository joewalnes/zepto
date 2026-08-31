#!/usr/bin/env bash
# QA-NAV-010: Cursor stays in viewport during vertical navigation
#
# NOTE: the previous version of this script tested a claim its own
# qa/07_navigation.txt entry never actually makes: that Ctrl+Up/Down
# "scrolls the viewport without moving the cursor". Investigated via
# interactive `hangon` testing (see bugs.md FIXED writeup for QA-NAV-010/
# QA-REG-070/etc.) — Zepto's up/down key dispatch (Editor.pm) never
# branches on the ctrl modifier at all, so Ctrl+Down currently behaves
# identically to plain Down (confirmed live: pressing ctrl-down moves the
# cursor from 1:1 to 2:1, viewport doesn't scroll independently). That
# claim was never real, documented, or reachable from the UI — no such
# assertion appears in qa/07_navigation.txt's actual QA-NAV-010 entry.
#
# What QA-NAV-010 actually documents (and this script now tests): "Press
# Down repeatedly. Cursor remains visible. Viewport auto-scrolls." That
# behavior is real (View::ensure_cursor_visible, called from move_down).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-010: Cursor stays in viewport during vertical nav"

content=""
for i in $(seq 1 60); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "nav010.txt" "$content")
qa_start "$file"

# Press Down well past a single screen's worth of lines (viewport is
# ~20 rows), so the viewport MUST auto-scroll to keep the cursor visible.
for i in $(seq 1 30); do
    qa_keys "down" 0.05
done
sleep 0.3

qa_assert_cursor_at "31" "cursor advanced to line 31 after 30x Down"

# The real regression this guards against: if View::ensure_cursor_visible
# stopped following the cursor, line 31 would have scrolled off the top
# of a viewport still pinned near line 1, and its content would not
# appear anywhere on screen.
qa_assert_screen "line 31 content" "viewport auto-scrolled to keep the cursor's line visible"

qa_keys "ctrl-q"
qa_summary
