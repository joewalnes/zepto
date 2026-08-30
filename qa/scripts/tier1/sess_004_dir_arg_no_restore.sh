#!/usr/bin/env bash
# QA-SESS-004 / QA-REG-116: A directory-arg (tree-focus) launch does not
# restore the saved session, and — critically — does not wipe it either.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-004: Directory-arg launch doesn't restore or clobber"

qa_project; dir="$QA_PROJECT_DIR"
printf 'alpha\n' > a.txt
printf 'beta\n' > b.txt

# 1) Bare launch, open both files, quit — saves a session.
qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-o"
qa_send "b.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# 2) Launch with a directory arg (tree-focus mode) and quit immediately
#    without opening anything. "█ name ⌥N" is the tab-bar decoration —
#    distinct from the file tree sidebar, which lists a.txt/b.txt as
#    directory entries regardless of what's open as a tab.
qa_restart .
qa_assert_screen "█ \[untitled\] ⌥1" "directory-arg launch shows an empty untitled tab"
qa_assert_not_screen "█ a\.txt ⌥" "directory-arg launch did not restore the saved session"
qa_keys "ctrl-q"
sleep 0.4

# 3) Bare relaunch — the saved session must have survived step 2.
qa_restart
qa_wait_screen "█ b\.txt ⌥2" 5
qa_assert_screen "█ a\.txt ⌥1" "saved session (a.txt) survived the directory-arg browse"
qa_assert_screen "█ b\.txt ⌥2" "saved session (b.txt) survived the directory-arg browse"

qa_keys "ctrl-q"
qa_summary
