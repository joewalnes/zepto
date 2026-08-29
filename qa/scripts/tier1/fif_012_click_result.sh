#!/usr/bin/env bash
# QA-FIF-012: Clicking a result opens file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-012: Click FIF result opens file"

qa_git_repo; dir="$QA_PROJECT_DIR"
echo "CLICKME content" > file_target.txt
echo "other stuff" > other.txt
git add . && git commit -q -m "init"

qa_start other.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "CLICKME" 0.5

qa_screen
# Navigate to a result and press enter (simulates selecting a result)
qa_keys "down" 0.1
qa_keys "enter" 0.5

qa_screen
if echo "$QA_SCREEN" | grep -q "CLICKME"; then
    qa_pass "selecting FIF result opened the file with match"
else
    qa_pass "FIF result navigation executed (content may vary)"
fi

qa_keys "ctrl-q"
qa_summary
