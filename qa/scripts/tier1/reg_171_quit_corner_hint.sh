#!/usr/bin/env bash
# QA-REG-171: Quit (⌃Q) has an always-visible on-screen hint in the
# DOCUMENT context tab bar, and the hint actually works.
# Bug: `quit` was priority => 0 in CommandRegistry.pm (never a status-bar
# pill) AND had no coverage in the tab bar's hardcoded corner hint either
# (unlike close/next/prev-tab, which rendered there even at priority 0) —
# confirmed absent in every tested width/theme/context. See bugs.md
# "Discoverability Contract gaps".
# Fix: added Quit to the same tab-bar corner-hint region as close/next/
# prev-tab (Renderer.pm::_render_tab_bar).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-171: Quit has an on-screen hint in the tab bar corner"

file=$(qa_tmpfile_nl "reg171.txt" "hello world")
qa_start "$file"
qa_assert_expect "reg171" "file is open"

# The tab bar's right-aligned corner hint should mention Quit somewhere.
# Default hangon terminal size (80 cols) is wide enough for the labeled
# form ("⌃Q Quit"); tests/renderer.t covers the narrower compact-pill
# fallback (see QA-REG-230) deterministically since hangon sessions here
# can't easily be resized. Title Case since the 2026-09-01 pill-styling
# conversion (bugs.md "Tab-bar buttons... use a visually different
# style" — was lowercase "quit").
qa_assert_screen "Quit" "Tab bar corner hint mentions 'Quit'"

# Functional check, not just cosmetic: the hint must correspond to a real,
# working shortcut.
qa_keys "ctrl-q"
sleep 0.5
if qa_alive 2>/dev/null; then
    qa_fail "⌃Q actually quits the editor" "process still alive after ⌃Q"
else
    qa_pass "⌃Q actually quits the editor"
fi

qa_summary
