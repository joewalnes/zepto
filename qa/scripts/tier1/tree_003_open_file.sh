#!/usr/bin/env bash
# QA-TREE-003: Enter in tree opens file in editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-003: Tree opens file"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree003_XXXXXX)
echo "content_aaa" > "$proj_dir/aaa.txt"
echo "content_bbb" > "$proj_dir/bbb.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start aaa.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Navigate to bbb.txt
qa_keys "down" 0.2

# Enter to open
qa_keys "enter" 0.3

# Should now have bbb.txt content in editor
qa_assert_expect "content_bbb" "tree enter opened bbb.txt"

qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
