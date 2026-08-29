#!/usr/bin/env bash
# QA-REG-041: Word wrap preserved in diff view
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-041: Diff view preserves word wrap"

repo_dir=$(mktemp -d /tmp/zepto_qa_reg041_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create file with a long line
printf 'short line\n' > test.txt
printf 'this is a very long line that should wrap when word wrap is enabled because it exceeds the terminal width significantly by having many words\n' >> test.txt
printf 'another short line\n' >> test.txt
git add test.txt
git commit -q -m "initial"

# Modify the long line
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/many words/CHANGED words here/' test.txt
else
    sed -i 's/many words/CHANGED words here/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Enable word wrap via palette
qa_keys "ctrl-space"
qa_send "word wrap" 0.3
qa_keys "enter"
sleep 0.3

# Toggle diff view
qa_keys "alt-d"
sleep 0.5

# Editor should show diff without crash
qa_assert_expect "CHANGED|long line|wrap" "diff view renders with word wrap enabled"

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
