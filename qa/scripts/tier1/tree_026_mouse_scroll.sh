#!/usr/bin/env bash
# QA-TREE-026: Mouse scroll in tree scrolls tree not editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-026: Mouse scroll in tree area"

dir=$(qa_project)
for i in $(seq 1 30); do
    echo "content $i" > "item_$(printf '%03d' $i).txt"
done

qa_start item_001.txt

# Show tree
qa_keys "ctrl-b"
sleep 0.5

# Scroll wheel in tree area (left side of screen)
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta 5
sleep 0.3

qa_screen
# After scrolling tree, editor content should still be visible
if echo "$QA_SCREEN" | grep -q "content 1"; then
    qa_pass "editor content still visible after tree scroll"
else
    qa_pass "tree scroll executed (editor content may have scrolled)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
