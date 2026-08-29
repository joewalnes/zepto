#!/usr/bin/env bash
# QA-TREE-015: Tree updates after Save As creates new file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-015: Tree refreshes on Save As"

qa_project; dir="$QA_PROJECT_DIR"
echo "existing" > existing.txt

qa_start existing.txt

# Show tree
qa_keys "ctrl-b"
sleep 0.3
qa_keys "escape"

# Create new tab
qa_keys "ctrl-n"
qa_send "new content"

# Save As — create new file in project dir
qa_keys "ctrl-s" 0.3
qa_send "$dir/newfile.txt"
qa_keys "enter" 0.5

# Check tree shows new file
qa_keys "ctrl-b"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -q "newfile"; then
    qa_pass "tree shows newly saved file"
else
    qa_fail "tree does not show newly saved file"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
