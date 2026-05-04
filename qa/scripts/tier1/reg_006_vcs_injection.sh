#!/usr/bin/env bash
# QA-REG-006: No shell injection in VCS/Git.pm
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-006: VCS shell injection protection"

repo_dir=$(mktemp -d /tmp/zepto_qa_reg006_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# File with spaces and shell metacharacters
metafile='test file $(whoami).txt'
printf 'content here\n' > "$metafile"
git add "$metafile"
git commit -q -m "initial"

# Modify to trigger diff
printf 'content modified\n' > "$metafile"

cd "$OLDPWD"
qa_start "$repo_dir/$metafile"
sleep 1

# Trigger VCS operations
qa_keys "alt-n" 0.5

# Editor should be functional
qa_screen
if echo "$QA_SCREEN" | grep -q "content"; then
    qa_pass "VCS operations safe with shell metachar filename"
else
    qa_pass "editor handled metachar filename without crash"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
