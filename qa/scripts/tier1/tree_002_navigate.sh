#!/usr/bin/env bash
# QA-TREE-002: Arrow keys navigate tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-002: Tree navigation"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree002_XXXXXX)
echo "content_aaa" > "$proj_dir/aaa.txt"
echo "content_bbb" > "$proj_dir/bbb.txt"
echo "content_ccc" > "$proj_dir/ccc.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start aaa.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Should show files
qa_assert_expect "aaa" "tree shows aaa.txt"
qa_assert_expect "bbb" "tree shows bbb.txt"

# Navigate down
qa_keys "down" 0.2
qa_keys "down" 0.2

# Preview should update — check that different content appears
qa_screen
if echo "$QA_SCREEN" | grep -qE "content_bbb|content_ccc"; then
    qa_pass "tree navigation updated preview"
else
    qa_fail "tree navigation updated preview"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
