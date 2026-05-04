#!/usr/bin/env bash
# QA-PICK-006: File picker respects .gitignore
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-006: Picker respects .gitignore"

# Resolve zepto path before cd
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

# Create a git repo with .gitignore
repo_dir=$(mktemp -d /tmp/zepto_qa_pick006_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "*.log" > .gitignore
echo "content" > main.txt
git add .gitignore main.txt
git commit -q -m "initial"
echo "should be hidden" > test_pick006.log

qa_start main.txt

# Open picker
qa_keys "ctrl-o"
sleep 0.5

# Search for the .log file
qa_send "pick006" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "test_pick006.log"; then
    qa_fail "gitignored file NOT shown in picker" "test_pick006.log found"
else
    qa_pass "gitignored file NOT shown in picker"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$repo_dir"
qa_summary
