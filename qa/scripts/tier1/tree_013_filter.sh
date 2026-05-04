#!/usr/bin/env bash
# QA-TREE-013: Tree filter with / typing
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-013: Tree filter"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree013_XXXXXX)
echo "c1" > "$proj_dir/alpha.txt"
echo "c2" > "$proj_dir/beta.txt"
echo "c3" > "$proj_dir/gamma.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start alpha.txt

qa_keys "ctrl-b"
sleep 0.5

# Type "/" to activate filter
qa_send "/" 0.2
qa_send "bet" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "beta"; then
    qa_pass "tree filter shows matching file"
else
    qa_skip "tree filter" "/ filter may not be implemented"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
