#!/usr/bin/env bash
# QA-PICK-017: All project files discoverable (no artificial cap)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-017: No file cap in picker"

dir=$(qa_git_repo)
# Create many files
for i in $(seq 1 100); do
    echo "content $i" > "item_$(printf '%04d' $i).txt"
done
# Create a distinctly named file
echo "unique needle" > unique_needle_file.txt
git add . && git commit -q -m "init"

qa_start item_0001.txt

qa_keys "ctrl-p" 0.5
qa_send "unique_needle" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "unique_needle"; then
    qa_pass "specific file found among 100+ files"
else
    qa_fail "specific file not found in large project"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
