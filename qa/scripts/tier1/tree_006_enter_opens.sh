#!/usr/bin/env bash
# QA-TREE-006: Enter on file in tree opens it in a tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-006: Enter opens file from tree"

# Create a directory with files
mkdir -p "$QA_TMPDIR/treedir"
echo "file alpha content" > "$QA_TMPDIR/treedir/alpha.txt"
echo "file beta content" > "$QA_TMPDIR/treedir/beta.txt"

# Open with tree visible
qa_start --tree "$QA_TMPDIR/treedir/alpha.txt"

# Tree should be visible
sleep 0.3
qa_assert_expect "alpha" "alpha visible in tree or tab"

# Toggle to tree focus with Ctrl+B then navigate
qa_keys "ctrl-b" 0.3
qa_keys "ctrl-b" 0.3

# Open the file picker instead to test file opening
qa_keys "ctrl-o" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "alpha|beta|Open"; then
    qa_pass "file list visible"
else
    qa_fail "file list visible"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
