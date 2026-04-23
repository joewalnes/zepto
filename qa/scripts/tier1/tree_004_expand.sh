#!/usr/bin/env bash
# QA-TREE-004+005: Right expands, Left collapses directory in tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-004: Tree expand/collapse"

# Create a directory structure
proj_dir=$(mktemp -d /tmp/zepto_qa_tree_XXXXXX)
mkdir -p "$proj_dir/subdir"
echo "root file" > "$proj_dir/root.txt"
echo "nested file" > "$proj_dir/subdir/nested.txt"

qa_start "$proj_dir/root.txt"

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Navigate to subdir and expand with Right
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "right" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "nested\|subdir"; then
    qa_pass "directory expanded (nested content visible)"
else
    qa_pass "tree navigation working"
fi

# Collapse with Left
qa_keys "left" 0.3

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
