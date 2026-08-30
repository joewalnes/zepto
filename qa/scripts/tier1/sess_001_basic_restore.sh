#!/usr/bin/env bash
# QA-SESS-001: Basic session restore — tabs, active tab, cursor position
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-001: Basic session restore"

qa_project; dir="$QA_PROJECT_DIR"
printf 'aaa\nbbb\nccc\nddd\neee\n' > a.txt
printf '111\n222\n333\n' > b.txt

# Bare launch (no file args) — required for both restore AND save to be
# eligible for this directory (see Editor.pm _session_eligible).
qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "down" 0.2
qa_keys "down" 0.2

qa_keys "ctrl-o"
qa_send "b.txt" 0.3
qa_keys "enter" 0.3
qa_keys "down" 0.2
qa_keys "right" 0.2
qa_assert_cursor_at "2:2" "b.txt cursor before quit"

qa_keys "ctrl-q"
sleep 0.4

# Relaunch with NO arguments from the same directory. Assertions use the
# "█ name ⌥N" tab-bar decoration specifically — the file tree sidebar
# (visible by default) also lists every file in the directory on its own
# row, and since it renders side-by-side with the tab bar in the flat
# terminal capture, a bare "a\.txt" match would false-pass even if the
# tab bar were empty.
qa_restart
qa_wait_screen "█ b\.txt ⌥2" 5

qa_assert_screen "█ a\.txt ⌥1" "a.txt tab restored"
qa_assert_screen "█ b\.txt ⌥2" "b.txt tab restored"
qa_assert_cursor_at "2:2" "active tab (b.txt) cursor position restored"

qa_keys "alt-," 0.3
qa_assert_cursor_at "3:1" "a.txt cursor position restored after switching tabs"

qa_keys "ctrl-q"
qa_summary
