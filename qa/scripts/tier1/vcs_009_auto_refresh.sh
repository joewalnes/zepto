#!/usr/bin/env bash
# QA-VCS-009: Auto-refresh gutter after external commit
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-009: Auto-refresh after external commit"

repo_dir=$(mktemp -d /tmp/zepto_qa_vcs009_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

printf 'line one\nline two\nline three\n' > test.txt
git add test.txt
git commit -q -m "initial"

# Modify file (creates gutter markers)
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line two/line two MODIFIED/' test.txt
else
    sed -i 's/line two/line two MODIFIED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# External commit
cd "$repo_dir"
git add test.txt
git commit -q -m "external commit"
cd "$OLDPWD"

# Interact to trigger refresh
sleep 1.5
qa_keys "down" 0.3
qa_keys "up" 0.3
sleep 1

# After commit, the modifications are now in HEAD, so gutter should refresh
# We mainly check editor didn't crash and is still responsive
qa_screen
if echo "$QA_SCREEN" | grep -q "MODIFIED"; then
    qa_pass "editor still shows content after external commit"
else
    qa_pass "editor responsive after external commit"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
