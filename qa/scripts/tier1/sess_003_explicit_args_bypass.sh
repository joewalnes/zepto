#!/usr/bin/env bash
# QA-SESS-003 / QA-REG-115: Explicit file args bypass restore, and a
# one-off explicit-file launch must never clobber a saved session.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-003: Explicit args bypass and don't clobber session"

qa_project; dir="$QA_PROJECT_DIR"
printf 'alpha\n' > a.txt
printf 'beta\n' > b.txt
printf 'gamma\n' > c.txt

# 1) Bare launch, open a.txt + b.txt, quit — saves a session.
qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-o"
qa_send "b.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# 2) One-off launch with an explicit file NOT in the saved session.
# Assertions use the "█ name ⌥N" tab-bar decoration, not a bare filename
# match — the file tree sidebar (visible by default) lists every file in
# the directory on its own row, and renders on the same physical terminal
# row as the tab bar, so a bare "a\.txt" match would false-pass.
qa_restart c.txt
qa_assert_screen "█ c\.txt ⌥1" "explicit file c.txt opened"
qa_assert_not_screen "█ a\.txt ⌥" "saved session (a.txt) not opened alongside explicit arg"
qa_keys "ctrl-q"
sleep 0.4

# 3) Bare relaunch — the saved a.txt/b.txt session must still be intact.
qa_restart
qa_wait_screen "█ b\.txt ⌥2" 5
qa_assert_screen "█ a\.txt ⌥1" "saved session (a.txt) survived the one-off explicit launch"
qa_assert_screen "█ b\.txt ⌥2" "saved session (b.txt) survived the one-off explicit launch"

qa_keys "ctrl-q"
qa_summary
