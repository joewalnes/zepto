#!/usr/bin/env bash
# QA-TREE-001: Ctrl+B toggles file tree visibility
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-001: Ctrl+B toggles file tree"

# Launch with --no-tree to start hidden, then toggle
file=$(qa_tmpfile_nl "tree001.txt" "test content")
qa_start --no-tree "$file"

# Tree should be hidden — capture initial state
qa_screen
initial_screen="$QA_SCREEN"

# Toggle tree on
qa_keys "ctrl-b"

# Tree should now be visible — look for tree indicators
# (vertical border, file entries, or changed layout)
qa_screen
if [[ "$QA_SCREEN" != "$initial_screen" ]]; then
    qa_pass "Ctrl+B changed the layout (tree appeared)"
else
    qa_fail "Ctrl+B did not change layout"
fi

# Toggle tree off
qa_keys "ctrl-b"  # unfocus or toggle
qa_keys "escape" 0.3  # ensure back to editor if just focused
qa_keys "ctrl-b" 0.3  # toggle visibility if first ctrl-b just focused

# Return to editing
qa_keys "escape" 0.3
qa_assert_screen "test content" "editor content still visible"

qa_keys "ctrl-q"

qa_summary
