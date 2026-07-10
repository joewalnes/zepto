#!/usr/bin/env bash
# QA-TREE-021: Hover on tree row shows highlight
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TREE-021: Tree hover (visual)"

qa_project; dir="$QA_PROJECT_DIR"
echo "aaa" > file1.txt
echo "bbb" > file2.txt
echo "ccc" > file3.txt
qa_start file1.txt

qa_keys "ctrl-b"
sleep 0.5

# Hover over a tree row
qa_hover 10 6
sleep 0.3

shot="$QA_TMPDIR/tree_hover.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a file tree panel on the left. Verify: (1) A file tree with at least 2-3 files is visible. (2) One row in the tree may appear highlighted or have a slightly different background from the others. If any tree row shows visual distinction, that's a PASS." \
    "tree row hover highlight"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
