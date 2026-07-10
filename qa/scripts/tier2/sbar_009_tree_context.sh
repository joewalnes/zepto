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

# Start with tree visible (via qa_start for state-dir isolation + env
# forwarding — see qa-helpers.sh qa_start comments on hangon/tmux env
# laundering)
qa_start .

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
    "This shows a terminal text editor with a FILE TREE panel focused on the left side. Look at the BOTTOM STATUS BAR. MUST be visible: (1) The status bar content is CLEARLY DIFFERENT from a normal document-editing status bar — it shows tree-navigation-specific pills or hints (e.g. things like navigation arrows, fold/open, or filter hints — exact wording may vary, but the content must be tree-oriented, not generic document-editing pills like cursor line:column). (2) The status bar still extends across the full width of the terminal. MUST NOT be true: the status bar must NOT look identical to a plain document-editing status bar (e.g. must NOT simply show an unchanged line:column cursor-position pill with no tree-specific content). If you cannot tell from the screenshot that the status bar content changed to something tree-specific, FAIL." \
    "Tree focus shows tree-specific status bar content, not the generic editing pills"

qa_keys "escape" 0.2
qa_keys "ctrl-q"

qa_summary
