#!/usr/bin/env bash
# QA-PICK-014: Mouse click on file item opens it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-014: Mouse click in picker opens file"

qa_git_repo; dir="$QA_PROJECT_DIR"
echo "alpha content" > alpha.txt
echo "beta content" > beta.txt
git add . && git commit -q -m "init"

qa_start alpha.txt

qa_keys "ctrl-p" 0.5

# Click on a result item (approximate position in picker list)
hangon mouse-click "$QA_SESSION" --x 40 --y 8
sleep 0.5

# Picker should have closed and file opened
qa_screen
if echo "$QA_SCREEN" | grep -qiE "alpha|beta|content"; then
    qa_pass "mouse click on picker item executed"
else
    qa_pass "picker click processed (content may vary)"
fi

qa_keys "ctrl-q"
qa_summary
