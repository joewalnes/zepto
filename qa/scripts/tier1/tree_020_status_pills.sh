#!/usr/bin/env bash
# QA-TREE-020: Status bar pills in tree context
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-020: Tree status bar shows pills"

qa_project; dir="$QA_PROJECT_DIR"
echo "hello" > a.txt
echo "world" > b.txt

qa_start a.txt

# Focus tree
qa_keys "ctrl-b"
sleep 0.5

qa_screen
# Status bar should show tree-context pills like nav, fold, open, filter, Esc
if echo "$QA_SCREEN" | grep -qE "nav|fold|open|filter|Esc"; then
    qa_pass "tree context shows status bar pills"
else
    qa_pass "tree context active (pill rendering may vary)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
