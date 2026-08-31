#!/usr/bin/env bash
# QA-REG-180: Tab bar caps use the ◢/◣ diagonal-triangle glyphs.
# Bug: user feedback "Tabs: really dont look great. Make them more
# 'tabby'". Diagnosed via a zoomed-in *hangon screenshot* crop of
# Renderer.pm::_render_tab_bar: the ◢/◣ (U+25E2/25E3) diagonal-corner
# glyphs each appeared to fill only a thin 1-cell wedge, and inactive tabs
# had no background fill at all to compensate. A same-day redesign
# temporarily replaced the triangles with a full-block glyph (█, U+2588).
#
# That premise turned out to be wrong: the "nearly invisible triangle" was
# a hangon screenshot rendering bug, not a real terminal limitation — the
# user confirmed on their actual terminal the triangles always rendered
# full-height. hangon was fixed (see hangon's CHANGELOG, "Fix three
# screenshot PNG rendering bugs" — geometric-shape characters like ◢/◣ are
# now drawn as cell-filling vector polygons instead of via font glyph
# outlines) and re-verified pixel-by-pixel against the fix. The cap glyph
# was reverted back to ◢/◣ accordingly. See bugs.md "Tab bar visual
# redesign (2026-08-30)" for the full before/after/re-revert writeup.
#
# The one independently-real fix from the redesign — inactive/hover tabs
# getting an actual background fill instead of none at all — is unrelated
# to cap glyph shape and was kept (see Theme.pm "Tabby redesign" comments).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-180: Tab bar uses ◢/◣ diagonal-triangle caps"

file1=$(qa_tmpfile_nl "reg180_a.txt" "content of file A")
file2=$(qa_tmpfile_nl "reg180_b.txt" "content of file B")
qa_start "$file1" "$file2"
qa_assert_expect "reg180_a" "tab bar visible with two tabs"

# The rendered screen (character grid, not raw ANSI) must contain the
# ◢/◣ triangle cap glyphs — a tautology-proof check since these are
# distinct, specific Unicode code points that only this feature emits in
# this simple no-tree/no-VCS-hunk repro.
qa_assert_screen "◢" "◢ triangle cap glyph present in the tab bar"
qa_assert_screen "◣" "◣ triangle cap glyph present in the tab bar"

# Sanity: both tab labels and their shortcut affordance are still there —
# only the cap glyph reverted, not the functional content of a tab.
qa_assert_screen "reg180_a" "First tab label still visible"
qa_assert_screen "reg180_b" "Second tab label still visible"
qa_assert_screen "⌥1" "Tab 1's ⌥N shortcut hint still visible"
qa_assert_screen "⌥2" "Tab 2's ⌥N shortcut hint still visible"

qa_keys "ctrl-q"
qa_summary
