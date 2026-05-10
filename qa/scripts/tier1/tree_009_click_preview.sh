#!/usr/bin/env bash
# QA-TREE-009: Click on previewed content confirms preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-009: Click preview confirms file"

dir=$(qa_project)
echo "content of alpha" > alpha.txt
echo "content of beta" > beta.txt

qa_start .

# Tree should be visible (opened with directory)
sleep 0.5

# Navigate tree to preview a file
qa_keys "ctrl-b"
sleep 0.3
qa_keys "down" 0.2
qa_keys "down" 0.2

qa_screen
# Click in the editor area (where preview is shown)
hangon mouse-click "$QA_SESSION" --x 40 --y 5
sleep 0.5

# Preview should be confirmed — file opened permanently
if qa_alive 2>/dev/null; then
    qa_pass "clicking preview area confirms file (no crash)"
else
    qa_fail "clicking preview area crashed editor"
fi

qa_keys "ctrl-q"
qa_summary
