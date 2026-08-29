#!/usr/bin/env bash
# QA-SESS-007: Sessions are isolated per working directory, not global
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-007: Per-directory session isolation"

dir_a="$QA_TMPDIR/proj_a"
dir_b="$QA_TMPDIR/proj_b"
mkdir -p "$dir_a" "$dir_b"
printf 'only in A\n' > "$dir_a/a.txt"
printf 'only in B\n' > "$dir_b/b.txt"

# Save a session for project A.
cd "$dir_a"
qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# Save a different session for project B (same state dir, different cwd).
cd "$dir_b"
qa_restart
qa_keys "ctrl-o"
qa_send "b.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# Relaunch bare from A — must restore a.txt only.
cd "$dir_a"
qa_restart
qa_wait_screen "a\.txt" 5
qa_assert_screen "a\.txt" "project A restores its own file"
qa_assert_not_screen "b\.txt" "project A's session does not include project B's file"
qa_keys "ctrl-q"
sleep 0.4

# Relaunch bare from B — must restore b.txt only.
cd "$dir_b"
qa_restart
qa_wait_screen "b\.txt" 5
qa_assert_screen "b\.txt" "project B restores its own file"
qa_assert_not_screen "a\.txt" "project B's session does not include project A's file"

qa_keys "ctrl-q"
qa_summary
