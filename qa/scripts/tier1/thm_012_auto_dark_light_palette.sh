#!/usr/bin/env bash
# QA-THM-012: Theme: Auto / Dark / Light are discoverable and directly
# selectable from the command palette (three-valued theme preference).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-012: Theme mode palette entries"

file=$(qa_tmpfile_nl "thm012.txt" "hello")
qa_start "$file"

# Discoverability: all three explicit-mode entries show up under "theme"
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect "Theme: Auto" "Theme: Auto entry visible in palette"
qa_assert_expect "Theme: Dark" "Theme: Dark entry visible in palette"
qa_assert_expect "Theme: Light" "Theme: Light entry visible in palette"
qa_keys "escape"
qa_keys "escape"

# Fresh state dir defaults to explicit dark
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect '\[dark\]' "Fresh state starts explicit dark"
qa_keys "escape"
qa_keys "escape"

# Selecting "Theme: Light" jumps directly to light (no need to go via ^T)
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "down" 0.2   # Theme: Auto
qa_keys "down" 0.2   # Theme: Dark
qa_keys "down" 0.2   # Theme: Light
qa_keys "enter" 0.4
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect '\[light\]' "Theme: Light selected directly sets light"
qa_keys "escape"
qa_keys "escape"

# Selecting "Theme: Dark" jumps directly back to dark
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "down" 0.2   # Theme: Auto
qa_keys "down" 0.2   # Theme: Dark
qa_keys "enter" 0.4
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect '\[dark\]' "Theme: Dark selected directly sets dark"
qa_keys "escape"
qa_keys "escape"

qa_keys "ctrl-q"
qa_summary
