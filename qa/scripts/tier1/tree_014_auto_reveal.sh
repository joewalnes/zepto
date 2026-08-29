#!/usr/bin/env bash
# QA-TREE-014: Current file auto-reveals in tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-014: Auto-reveal"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree014_XXXXXX)
mkdir -p "$proj_dir/subdir"
echo "deep" > "$proj_dir/subdir/deep.txt"
echo "root" > "$proj_dir/root.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start subdir/deep.txt

qa_keys "ctrl-b"
sleep 0.5

# The file being edited should be visible/highlighted in tree
qa_assert_expect "deep" "current file visible in tree"

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
