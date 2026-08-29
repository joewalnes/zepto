#!/usr/bin/env bash
# QA-SBAR-019: Tutorial (F1) is no longer a status bar pill — it has no
# ⌃/⌥ modifier so it doesn't fit either grouped column. Still reachable
# via the command palette and the F1 key itself (behavioral discovery).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-019: Tutorial removed from status bar pills"

file=$(qa_tmpfile_nl "sbar019.txt" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"
qa_assert_not_screen "Tutorial" "no Tutorial pill on the status bar"

# Still discoverable via the command palette.
qa_keys "ctrl-space"
qa_send "Tutorial" 0.3
qa_assert_screen "Tutorial" "Tutorial listed in command palette"
qa_assert_screen "F1" "Tutorial palette entry shows its F1 shortcut"
qa_keys "escape"
qa_keys "escape"

# Still bound directly to F1.
qa_keys "f1"
qa_assert_screen "Tutorial|Zepto" "F1 opens the Tutorial doc directly"
qa_keys "escape"

qa_keys "ctrl-q"
qa_summary
