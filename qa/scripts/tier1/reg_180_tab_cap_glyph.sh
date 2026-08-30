#!/usr/bin/env bash
# QA-REG-180: Tab bar caps use the solid full-block glyph, not the old
# diagonal-triangle notches.
# Bug: user feedback "Tabs: really dont look great. Make them more
# 'tabby'". Diagnosed via a zoomed-in screenshot crop of
# Renderer.pm::_render_tab_bar: the ◢/◣ (U+25E2/25E3) diagonal-corner
# glyphs each filled only a thin 1-cell wedge — confirmed nearly invisible
# at normal (non-zoomed) viewing size — and inactive tabs had no
# background fill at all to compensate. See bugs.md "Tab bar visual
# redesign (2026-08-30)".
# Fix: both edges of every tab (active/inactive/hover) now use a single
# full-block glyph (█, U+2588 — already used elsewhere in this file for
# the VCS gutter's expanded-hunk indicator, so no new font dependency).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-180: Tab bar uses full-block caps, not diagonal notches"

file1=$(qa_tmpfile_nl "reg180_a.txt" "content of file A")
file2=$(qa_tmpfile_nl "reg180_b.txt" "content of file B")
qa_start "$file1" "$file2"
qa_assert_expect "reg180_a" "tab bar visible with two tabs"

# The rendered screen (character grid, not raw ANSI) must contain the new
# full-block cap glyph and must NOT contain either of the old diagonal
# triangle glyphs — a tautology-proof check since these are distinct,
# specific Unicode code points that only this feature emits.
qa_assert_screen "█" "Full-block cap glyph (█) present in the tab bar"
qa_assert_not_screen "◢" "Old ◢ diagonal-triangle glyph is gone"
qa_assert_not_screen "◣" "Old ◣ diagonal-triangle glyph is gone"

# Sanity: both tab labels and their shortcut affordance are still there —
# the redesign changed the cap glyph and fill colors only, not the
# functional content of a tab.
qa_assert_screen "reg180_a" "First tab label still visible"
qa_assert_screen "reg180_b" "Second tab label still visible"
qa_assert_screen "⌥1" "Tab 1's ⌥N shortcut hint still visible"
qa_assert_screen "⌥2" "Tab 2's ⌥N shortcut hint still visible"

qa_keys "ctrl-q"
qa_summary
