#!/usr/bin/env bash
# QA-SESS-006: Unsaved [untitled] buffers are never persisted or restored
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-006: Untitled buffers not saved in session"

qa_project; dir="$QA_PROJECT_DIR"
printf 'saved file\n' > a.txt

qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3

# New untitled tab — never saved.
qa_keys "ctrl-n"
qa_send "scratch text, never saved" 0.3
# Dirty tabs render a "●" marker between the name and the ⌥N shortcut
# (e.g. "◢ [untitled] ● ⌥2 ×◢"), so allow anything between them.
qa_assert_screen "◢ \[untitled\].*⌥2" "untitled tab open before quit"

qa_keys "ctrl-q"
# Untitled tab is dirty — expect the save-changes prompt; discard it.
sleep 0.3
qa_assert_screen "Save|Discard|Cancel" "save-changes prompt shown for the dirty untitled tab"
qa_send "n" 0.3
qa_assert_exited "editor exits after discarding"

qa_restart
qa_wait_screen "◢ a\.txt ⌥1" 5

qa_assert_screen "◢ a\.txt ⌥1" "saved file (a.txt) restored"
qa_assert_not_screen "\[untitled\]" "untitled buffer was not restored"

qa_keys "ctrl-q"
qa_summary
