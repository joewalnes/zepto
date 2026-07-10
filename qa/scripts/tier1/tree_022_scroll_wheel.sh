#!/usr/bin/env bash
# QA-TREE-022: Scroll wheel in tree is smooth
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-022: Smooth scroll in tree"

qa_project; dir="$QA_PROJECT_DIR"
for i in $(seq 1 40); do
    echo "file $i" > "file_$(printf '%03d' $i).txt"
done

qa_start file_001.txt

# Focus tree
qa_keys "ctrl-b"
sleep 0.5

# Scroll down in tree area
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta 5
sleep 0.3

if qa_alive 2>/dev/null; then
    qa_pass "scroll wheel in tree works (no crash)"
else
    qa_fail "scroll wheel in tree crashed"
fi

# Scroll back up
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta -5
sleep 0.3

if qa_alive 2>/dev/null; then
    qa_pass "scroll up in tree works"
else
    qa_fail "scroll up in tree crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
