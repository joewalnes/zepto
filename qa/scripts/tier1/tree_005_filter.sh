#!/usr/bin/env bash
# NOTE ON THIS SCRIPT'S ID: the catalog entry QA-TREE-005 (qa/22_file_tree.txt)
# is actually "Left collapses directory", unrelated to filtering — this
# script's filename/header predate that numbering and were never
# reconciled (same class of mismatch as bugs.md's "QA-FIND-007 catalog
# entry doesn't match find_007_replace_preview.sh" finding). Left in place
# under its original name rather than renumbered (CLAUDE.md: "IDs are
# stable — never renumber"); QA-TREE-013 is the catalog-correct entry for
# the '/' filter trigger itself (see tree_013_filter.sh).
#
# What this script actually covers: pressing '/' activates filter mode
# immediately (FileTree::start_filter), but with an EMPTY query the tree
# still shows the normal hierarchical view (FileTree comment: "empty query
# with filter_active still shows the normal hierarchical tree") — so plain
# arrow-key navigation and Enter-to-open must keep working right after '/'
# is pressed, before any characters are typed. This was a real edge case
# in the bugs.md P1 "File-tree flat-filter search... has zero UI trigger"
# fix: handle_tree_event's arrow/enter handling isn't gated on filter
# state, but it's worth locking in explicitly since it's exactly the kind
# of interaction a user hits in the first second after discovering '/'.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-005 (script): navigation works with filter active but empty"

qa_project
dir="$QA_PROJECT_DIR"
echo "alpha file content" > "$dir/afile.txt"
echo "bravo file content" > "$dir/bfile.txt"

qa_start afile.txt
qa_keys "ctrl-b" 0.3

# Activate filter mode but type nothing yet.
qa_send "/" 0.2
qa_assert_screen "Esc clear" "filter mode is active (hint row shows 'Esc clear') even with an empty query"
qa_assert_screen "bfile" "second file is still listed — empty query keeps the normal hierarchical view, not a blank flat list"

# Arrow-key navigation must still work in this state: cursor starts on
# afile.txt (revealed as the current file when the tree was focused),
# so "down" should move onto bfile.txt and preview it.
qa_keys "down" 0.3
qa_assert_expect "bravo file content" "down-arrow preview still works with filter active and query empty"

qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_keys "ctrl-q" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qi "unsaved\|discard\|save"; then
    qa_send "n" 0.2
fi

qa_summary
