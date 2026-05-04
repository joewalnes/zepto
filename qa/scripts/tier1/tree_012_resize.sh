#!/usr/bin/env bash
# QA-TREE-012: Tree can be resized with } and {
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-012: Tree resize with } and {"

mkdir -p "$QA_TMPDIR/treedir"
echo "content" > "$QA_TMPDIR/treedir/file.txt"

qa_start --tree "$QA_TMPDIR/treedir/file.txt"

# Focus the tree
qa_keys "ctrl-b" 0.3

# Capture initial screen
qa_screen
initial="$QA_SCREEN"

# Widen tree with }
qa_send "}"
sleep 0.3

qa_screen
after_widen="$QA_SCREEN"

if [[ "$after_widen" != "$initial" ]]; then
    qa_pass "} changed tree width (widened)"
else
    qa_fail "} changed tree width (widened)"
fi

# Shrink tree with {
qa_send "{"
sleep 0.3

qa_screen
after_shrink="$QA_SCREEN"

if [[ "$after_shrink" != "$after_widen" ]]; then
    qa_pass "{ changed tree width (shrunk)"
else
    qa_fail "{ changed tree width (shrunk)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
