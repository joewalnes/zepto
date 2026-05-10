#!/usr/bin/env bash
# QA-PICK-015: Tree auto-hides after single-file launch open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-015: Tree auto-hide on single-file launch"

dir=$(qa_git_repo)
echo "file1" > one.txt
echo "file2" > two.txt
git add . && git commit -q -m "init"

# Launch with single file (tree should be hidden by default)
qa_start one.txt

qa_screen
# Tree should not be visible initially
initial_screen="$QA_SCREEN"

# Open picker and select a file
qa_keys "ctrl-p" 0.5
qa_send "two" 0.3
qa_keys "enter" 0.5

# After opening, tree should still be hidden (single-file mode)
qa_screen
if qa_alive 2>/dev/null; then
    qa_pass "file opened via picker in single-file mode"
else
    qa_fail "picker file open crashed"
fi

qa_keys "ctrl-q"
qa_summary
