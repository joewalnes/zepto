#!/usr/bin/env bash
# QA-SESS-008: No saved session falls back to a single empty tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-008: No saved session -> empty tab fallback"

qa_project; dir="$QA_PROJECT_DIR"

# Fresh state dir, fresh project dir — no prior session could exist.
qa_start
qa_assert_screen "\[untitled\]" "bare launch with no saved session opens a single empty tab"
qa_assert_not_screen "⌥2" "exactly one tab is open, not multiple"

qa_keys "ctrl-q"
qa_summary
