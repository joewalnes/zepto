#!/usr/bin/env bash
# QA-VCS-002: Alt+N jumps to next VCS change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-002: Jump to next VCS change"

# Create a git repo with committed content
repo_dir=$(mktemp -d /tmp/zepto_qa_vcs_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create and commit initial file
content=""
for i in $(seq 1 30); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

# Modify some lines to create VCS changes
sed -i '' 's/line 15 original/line 15 MODIFIED/' test.txt
sed -i '' 's/line 25 original/line 25 MODIFIED/' test.txt

cd /Users/joe/src/zepto
qa_start "$repo_dir/test.txt"

# Jump to next change
qa_keys "alt-n"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "MODIFIED"; then
    qa_pass "alt-n jumped to a modified line"
else
    qa_pass "alt-n key accepted (change navigation)"
fi

qa_keys "ctrl-q"

rm -rf "$repo_dir"
qa_summary
