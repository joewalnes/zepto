#!/usr/bin/env bash
# QA-TREE-004+005: Right expands, Left collapses directory in tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-004: Tree expand/collapse"

# Create a directory structure with identifiable nested file
proj_dir=$(mktemp -d /tmp/zepto_qa_tree_XXXXXX)
mkdir -p "$proj_dir/mysubdir"
echo "root file" > "$proj_dir/root.txt"
echo "nested file" > "$proj_dir/mysubdir/deep_nested.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start root.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Verify mysubdir is in tree
qa_assert_screen "mysubdir" "mysubdir visible in tree"

# Before expand — nested file should not be visible
qa_assert_not_screen "deep_nested" "nested file hidden before expand"

# Navigate to ensure mysubdir is highlighted (down then up to activate)
qa_keys "down" 0.2
qa_keys "up" 0.2

# Expand with Right
qa_keys "right" 0.3

# After expand — nested file should be visible
qa_assert_screen "deep_nested" "nested file visible after expand"

# Collapse with Left
qa_keys "left" 0.3

# After collapse — nested file should be hidden again
qa_assert_not_screen "deep_nested" "nested file hidden after collapse"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
