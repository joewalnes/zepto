#!/usr/bin/env bash
# QA-REG-172: The tab bar's close/tab-nav corner hint shows plain-language
# labels, not just bare modifier glyphs, when there's room.
# Bug: the hint rendered as raw glyphs with zero labels ("⌃W ×  ⌥, ←  ⌥. →")
# — an LLM-vision discoverability sweep flagged this consistently (6/6
# relevant screenshots) as "unlabeled and ambiguous": it satisfied "on
# screen" but not "comprehensible to a first-time user" per
# docs/UI_GUIDELINES.md's Discoverability Contract. See bugs.md
# "Discoverability sweep run 2".
# Fix: Renderer.pm::_render_tab_bar now tries a labeled form ("⌃W close
# ⌥←/→ tabs ⌃Q quit") first, falling back to the original bare-glyph form
# only when there isn't room for labels (mirrors _fit_pill_group's
# full-form-first idiom).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-172: Tab bar corner hint shows plain-language labels"

file=$(qa_tmpfile_nl "reg172.txt" "hello world")
qa_start "$file"
qa_assert_expect "reg172" "file is open"

# Default hangon terminal (80 cols) has plenty of room for the labeled form.
qa_assert_screen "close" "Corner hint labels the close shortcut ('close')"
qa_assert_screen "tabs" "Corner hint labels the tab-nav shortcuts ('tabs')"
qa_assert_screen "quit" "Corner hint labels the quit shortcut ('quit')"

qa_keys "ctrl-q"
qa_summary
