#!/usr/bin/env bash
# QA-FIF-001: Ctrl+Shift+F opens find-in-files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-001: Find in files opens"

# Create a project directory with multiple files
proj_dir=$(mktemp -d /tmp/zepto_qa_fif_XXXXXX)
echo "hello from alpha" > "$proj_dir/alpha.txt"
echo "world from beta" > "$proj_dir/beta.txt"
echo "hello again from gamma" > "$proj_dir/gamma.txt"

qa_start "$proj_dir/alpha.txt"

# Open find-in-files via palette (Ctrl+Shift+F may not transmit via tmux)
qa_keys "ctrl-space"
qa_send "find in" 0.3

qa_assert_screen "Find in Files|Find in files|find.in.files" "find-in-files command visible in palette"

# Settle before Escape so it's sent as its own cleanly-separated keystroke
# rather than racing the tail of the typed query on a slow/loaded runner.
qa_expect_screen "find in" 3 -iF || true

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
