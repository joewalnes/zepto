#!/usr/bin/env bash
# QA-PREF-015: Tab Width settable from the command palette and persists
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-015: Tab Width palette command + persistence"

file=$(qa_tmpfile_nl "pref015.txt" "hello")

# Session 1: open the "Tab Width" command, verify it's prefilled with the
# current default (4), then change it to 2.
qa_start "$file"
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_assert_expect "Tab Width: 4" "Tab Width command discoverable via palette, prefilled with default (4)"

qa_send "2"
qa_keys "enter" 0.2
qa_assert_expect "Tab Width: 2" "Tab Width updated to 2"

qa_keys "ctrl-q"

# Session 2: relaunch — tab width should still be 2
qa_restart "$file"
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_assert_expect "Tab Width: 2" "Tab Width (2) persisted across restart"
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
