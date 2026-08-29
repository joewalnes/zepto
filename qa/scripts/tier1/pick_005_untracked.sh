#!/usr/bin/env bash
# QA-PICK-005: File picker shows untracked files in git repo
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-005: Picker shows untracked git files"

# Resolve zepto path before cd
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

# Create a git repo with an untracked file
repo_dir=$(mktemp -d /tmp/zepto_qa_pick005_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "tracked" > tracked.txt
git add tracked.txt
git commit -q -m "initial"
echo "untracked content" > untracked_pick005.txt

qa_start tracked.txt

# Open picker
qa_keys "ctrl-p" 0.5

# Type to filter
qa_send "untracked" 0.3

qa_assert_expect "untracked" "untracked file visible in picker"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$repo_dir"
qa_summary
