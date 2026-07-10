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
    "This shows a text editor with a file tree panel on the left, with the mouse cursor currently positioned over one row in the tree. MUST be visible: (1) A file tree with at least 2-3 file/folder rows. (2) EXACTLY the row under the mouse position has a visibly different background than the other tree rows (a highlight/hover fill). MUST NOT be true: all tree rows must NOT look identical — if every row has the same background with none standing out, FAIL. If the hovered row's highlight is not clearly distinguishable from the other rows in the screenshot, FAIL." \
    "the hovered tree row is visually distinct from its non-hovered neighbors"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
