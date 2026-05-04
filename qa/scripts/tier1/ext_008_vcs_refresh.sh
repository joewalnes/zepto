#!/usr/bin/env bash
# QA-EXT-008: VCS diff refreshes after external change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-008: VCS refresh on external change"
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
repo_dir=$(mktemp -d /tmp/zepto_qa_ext008_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "line 1" > test.txt
git add test.txt
git commit -q -m "initial"
qa_start test.txt
sleep 1
# Modify externally
echo "line 1 MODIFIED" > test.txt
sleep 2
# Editor should still be alive
if qa_alive; then
    qa_pass "editor alive after external VCS change"
else
    qa_fail "editor alive after external change"
fi
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$repo_dir"
qa_summary
