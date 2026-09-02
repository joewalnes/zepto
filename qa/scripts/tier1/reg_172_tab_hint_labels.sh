#!/usr/bin/env bash
# QA-REG-172: The tab bar's close/tab-nav corner hint shows plain-language
# labels, not just bare modifier glyphs, when there's room.
# Bug: the hint rendered as raw glyphs with zero labels ("⌃W ×  ⌥, ←  ⌥. →")
# — an LLM-vision discoverability sweep flagged this consistently (6/6
# relevant screenshots) as "unlabeled and ambiguous": it satisfied "on
# screen" but not "comprehensible to a first-time user" per
# docs/UI_GUIDELINES.md's Discoverability Contract. See bugs.md
# "Discoverability sweep run 2".
# Fix: Renderer.pm::_render_tab_bar now tries a labeled pill form ("⌃W
# Close  ⌥←/→ Tabs  ⌃Q Quit") first, falling back to a compact pill form
# only when there isn't room for labels (an atomic all-or-nothing fit
# across all three pills — see _fit_core_nav_hint_pills()).
#
# 2026-09-01: labels are now Title Case and rendered as rounded pills
# (was plain lowercase text with no pill shape at all) — see bugs.md
# "Tab-bar buttons (close/tabs/quit hints) use a visually different
# style than the bottom status bar's pills". Assertions below updated
# from lowercase to Title Case to match; QA-REG-229 covers the pill
# shape / overflow-at-narrow-width aspects of that same fix.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-172: Tab bar corner hint shows plain-language labels"

file=$(qa_tmpfile_nl "reg172.txt" "hello world")
qa_start "$file"
qa_assert_expect "reg172" "file is open"

# Default hangon terminal (80 cols) has plenty of room for the labeled form.
qa_assert_screen "Close" "Corner hint labels the close shortcut ('Close')"
qa_assert_screen "Tabs" "Corner hint labels the tab-nav shortcuts ('Tabs')"
qa_assert_screen "Quit" "Corner hint labels the quit shortcut ('Quit')"

qa_keys "ctrl-q"
qa_summary
