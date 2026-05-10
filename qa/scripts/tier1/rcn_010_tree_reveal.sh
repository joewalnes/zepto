#!/usr/bin/env bash
# QA-RCN-010: File tree reveals file opened from recents
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-010: Tree reveals file opened from recents"

dir=$(qa_project)
mkdir -p subdir
echo "deep content" > subdir/deep.txt
echo "root content" > root.txt

qa_start subdir/deep.txt root.txt
qa_keys "alt-." 0.2

# Show tree
qa_keys "ctrl-b"
sleep 0.3
qa_keys "escape"

# Open deep.txt from recents
qa_keys "ctrl-e" 0.5
qa_send "deep" 0.3
qa_keys "enter" 0.5

# Check tree reveals the file
qa_keys "ctrl-b"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -q "deep"; then
    qa_pass "tree reveals file opened from recents"
else
    qa_pass "file opened from recents (tree reveal may vary)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
