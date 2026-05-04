#!/usr/bin/env bash
# QA-CLI-011: ZEPTO_TREE=0 env var hides tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-011: ZEPTO_TREE=0 env var"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
proj_dir=$(mktemp -d /tmp/zepto_qa_cli011_XXXXXX)
echo "content" > "$proj_dir/test.txt"
cd "$proj_dir"

# Start with tree disabled — normally opening a dir shows tree
export ZEPTO_TREE=0
qa_start test.txt

# Tree should NOT be visible
qa_screen
# If tree were visible we'd see directory entries
if echo "$QA_SCREEN" | grep -q "test.txt.*test.txt"; then
    qa_fail "tree hidden with ZEPTO_TREE=0" "tree appears visible"
else
    qa_pass "tree hidden with ZEPTO_TREE=0"
fi

qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
