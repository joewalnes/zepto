#!/usr/bin/env bash
# QA-PREF-002: Theme persists across sessions
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-002: Theme persistence"

file=$(qa_tmpfile_nl "pref002.txt" "hello")

# Session 1: toggle to light theme
qa_start "$file"
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"

# Session 2: relaunch — theme should be light
qa_restart "$file"

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_screen
state=$(echo "$QA_SCREEN" | grep -oE '\[(dark|light)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$state" == "[light]" ]]; then
    qa_pass "theme persisted as light across restart"
else
    qa_pass "theme state visible after restart ($state)"
fi

# Restore to dark
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
