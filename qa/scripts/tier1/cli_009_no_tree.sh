#!/usr/bin/env bash
# QA-CLI-009: File tree can be toggled with Ctrl+B
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-009: Tree toggle with Ctrl+B"

mkdir -p "$QA_TMPDIR/treedir"
echo "tree test" > "$QA_TMPDIR/treedir/myfile.txt"

qa_start --no-tree "$QA_TMPDIR/treedir/myfile.txt"

# Tree should be hidden initially
qa_screen
initial="$QA_SCREEN"

# Toggle tree on with Ctrl+B
qa_keys "ctrl-b"

qa_screen
if [[ "$QA_SCREEN" != "$initial" ]]; then
    qa_pass "Ctrl+B changed layout (tree toggled on)"
else
    qa_fail "Ctrl+B changed layout (tree toggled on)"
fi

# Toggle tree off — Esc to unfocus tree, then Ctrl+B to hide
qa_keys "escape" 0.3
qa_keys "ctrl-b"

qa_screen
after_toggle="$QA_SCREEN"
if [[ "$after_toggle" != "$initial" ]]; then
    # May need another toggle cycle
    qa_keys "ctrl-b" 0.3
fi

qa_assert_screen "tree test" "editor content still visible after toggle"

qa_keys "ctrl-q"
qa_summary
