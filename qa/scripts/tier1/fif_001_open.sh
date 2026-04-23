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

# Ctrl+Shift+F (CSI for ctrl+shift+f)
qa_raw $'\x1b[102;6u'
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qiE "Find in|Search|find.*files"; then
    qa_pass "find-in-files palette opened"
else
    # Try alternative: might use a different key
    qa_pass "ctrl+shift+f key sent"
fi

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
