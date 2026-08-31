#!/usr/bin/env bash
# QA-SESS-009 / QA-PREF-015: "Restore Session on Startup" is discoverable
# via the command palette and actually controls restore behavior.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-009: Restore Session on Startup toggle"

qa_project; dir="$QA_PROJECT_DIR"
printf 'content\n' > a.txt

# Discoverable via fuzzy search in the command palette.
qa_start
qa_keys "ctrl-space"
qa_send "restore session" 0.3
qa_assert_expect "Restore Session on Startup" "command found via fuzzy palette search"
qa_assert_expect "\[on\]" "toggle shows default ON state"

# Turn it off.
qa_keys "enter" 0.3
qa_assert_expect "\[off\]" "toggle reflects OFF state immediately"
qa_keys "escape" 0.2

# Open a file, quit — session save is a no-op with the pref off.
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# "◢ name ⌥N" is the tab-bar decoration — distinct from the file tree
# sidebar, which lists a.txt as a directory entry regardless of whether
# it's open as a tab.
qa_restart
qa_assert_expect "◢ \[untitled\] ⌥1" "with the pref off, bare relaunch does not restore a.txt"
qa_assert_not_screen "◢ a\.txt ⌥" "a.txt tab is not reopened while restore_session is off"

qa_keys "ctrl-q"
qa_summary
