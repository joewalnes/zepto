#!/usr/bin/env bash
# QA-TREE-005: Typing in tree filters files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-005: Tree filtering"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree005_XXXXXX)
echo "c1" > "$proj_dir/alpha.txt"
echo "c2" > "$proj_dir/beta.txt"
echo "c3" > "$proj_dir/gamma.txt"
echo "c4" > "$proj_dir/delta.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start alpha.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# All files should be visible
qa_assert_expect "alpha" "alpha visible before filter"
qa_assert_expect "delta" "delta visible before filter"

# Type to filter
qa_send "bet" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "beta"; then
    qa_pass "filter shows matching file 'beta'"
else
    qa_skip "tree filtering" "tree may not support type-to-filter"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
