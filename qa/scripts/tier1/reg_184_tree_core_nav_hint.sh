#!/usr/bin/env bash
# QA-REG-184: The FILE_TREE-context status bar shows the same core-nav hint
# (close tab / switch tabs / quit) the DOCUMENT-context tab bar shows, when
# there's room. Previously the FILE_TREE context had no coverage for these
# at all (see bugs.md "P1: Discoverability Contract gaps... FILE_TREE
# context is missing on-screen hints for: quit... AND tab navigation").
# Fix: Renderer.pm::_core_nav_hint_pill_candidates() (formerly
# _core_nav_hint_text(), converted to rounded Title Case pills 2026-09-01 —
# see bugs.md "Tab-bar buttons... use a visually different style") is a
# single shared helper used by both _render_tab_bar (DOCUMENT context) and
# _render_context_status_bar (FILE_TREE context), so the wording/casing
# can't drift between the two contexts. This test asserts the FILE_TREE
# row renders the *identical* wording DOCUMENT context uses.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-184: FILE_TREE status bar shares the core-nav hint with DOCUMENT context"

qa_project; dir="$QA_PROJECT_DIR"
echo "hello" > a.txt
echo "world" > b.txt

qa_start a.txt
qa_assert_expect "a\.txt" "file is open"

# The FILE_TREE row has more fixed chrome (breadcrumb + tree-specific pills
# + Open/Commands pills) than the DOCUMENT tab bar, so it needs a wider
# terminal before there's room left over for the core-nav hint — confirmed
# via a direct-render probe that this starts appearing around 110 cols in
# nerd-font mode. 130 cols leaves comfortable headroom above that threshold
# so this test isn't flaky at the exact boundary.
qa_resize_window 130 24

qa_keys "ctrl-b"
sleep 0.5

qa_assert_screen "Close" "Tree status bar labels the close-tab shortcut ('Close')"
qa_assert_screen "Tabs" "Tree status bar labels the tab-nav shortcut ('Tabs')"
qa_assert_screen "Quit" "Tree status bar labels the quit shortcut ('Quit')"
qa_assert_screen "⌃Q" "Tree status bar shows the actual ⌃Q shortcut glyph for quit"

qa_keys "ctrl-q"
qa_summary
