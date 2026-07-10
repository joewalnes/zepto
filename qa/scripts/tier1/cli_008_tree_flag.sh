#!/usr/bin/env bash
# QA-CLI-008: --tree flag forces tree visible
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-008: --tree flag"

# Build a project dir with recognizable entries for the tree to show.
# (This test used to assert the tree showed "lib|docs|..." — repo-root
# entries — which silently relied on the runner leaving cwd at the repo
# root. qa_setup now starts every test in its own tmpdir, so assert on
# entries this test creates itself.)
qa_project
mkdir -p subdir_cli008
echo "hello" > cli008.txt
echo "x" > subdir_cli008/nested.txt

qa_start --tree cli008.txt

# Tree should be visible — look for our directory entries
qa_assert_screen "subdir_cli008" "tree panel shows directory entries"
qa_assert_screen "hello" "editor content still visible"

qa_keys "ctrl-q"
qa_summary
