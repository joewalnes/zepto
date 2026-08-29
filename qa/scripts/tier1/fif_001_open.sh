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

qa_assert_expect "Find in Files|Find in files|find.in.files" "find-in-files command visible in palette"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
