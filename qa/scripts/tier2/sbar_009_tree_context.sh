#!/usr/bin/env bash
# QA-SBAR-009: Tree focus shows tree-specific pills
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-009: Tree-specific status bar pills (visual)"

# Create a small project directory
projdir="$QA_TMPDIR/proj"
mkdir -p "$projdir/src"
echo "main content" > "$projdir/src/main.py"
echo "helper content" > "$projdir/src/helper.py"
echo "# README" > "$projdir/README.md"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$projdir"

# Start with tree visible
hangon start process --name "$QA_SESSION" -- "$QA_ZEPTO" .
sleep "$QA_RENDER_WAIT"

cd "$OLDPWD"

# Capture editor-focused status bar
shot_editor="$QA_TMPDIR/sbar_editor.png"
qa_screenshot "$shot_editor"

# Focus the tree
qa_keys "ctrl-b"
sleep 0.3

shot_tree="$QA_TMPDIR/sbar_tree.png"
qa_screenshot "$shot_tree"

qa_assert_visual "$shot_tree" \
    "This shows a terminal text editor with a FILE TREE panel focused on the left side. Look at the BOTTOM STATUS BAR. Verify: (1) The status bar content has CHANGED from a normal editor view — it now shows tree-specific information or pills. (2) The file tree on the left side is visually focused/active (may have a highlighted border or the cursor is in the tree). (3) The status bar may show tree-related controls, navigation hints, or a different set of pills than when the editor is focused. (4) The status bar still extends across the full width of the terminal." \
    "Tree focus shows tree-specific status bar content"

qa_keys "escape" 0.2
qa_keys "ctrl-q"

qa_summary
