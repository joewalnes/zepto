#!/usr/bin/env bash
# QA-TREE-023: Drag scrollbar in tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-023: Tree scrollbar drag"

dir=$(qa_project)
for i in $(seq 1 50); do
    echo "file $i" > "file_$(printf '%03d' $i).txt"
done

qa_start file_001.txt

# Focus tree
qa_keys "ctrl-b"
sleep 0.5

# Drag scrollbar area (right edge of tree panel, ~col 23)
hangon mouse-drag "$QA_SESSION" --from 22,5 --to 22,15 --steps 5
sleep 0.3

if qa_alive 2>/dev/null; then
    qa_pass "tree scrollbar drag works (no crash)"
else
    qa_fail "tree scrollbar drag crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
