#!/usr/bin/env bash
# QA-TREE-030: Enter opens the highlighted result while filtering, and
# exits filter mode afterward — mirrors QA-TREE-006's plain-mode Enter, but
# for the fuzzy-filter flat results view added by the fix for bugs.md P1
# "File-tree flat-filter search... has zero UI trigger".
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-030: Enter opens filtered result"

qa_project
dir="$QA_PROJECT_DIR"
mkdir -p "$dir/src"
echo "initial content" > "$dir/initial.txt"
echo "needle content" > "$dir/src/needle.txt"
echo "other content" > "$dir/src/haystack.txt"

qa_start initial.txt
qa_keys "ctrl-b" 0.3

qa_send "/" 0.2
qa_send "needle" 0.4
qa_assert_expect "needle" "filtered results show needle.txt"

qa_keys "enter" 0.4
qa_assert_expect "needle content" "Enter opened needle.txt — its content is now visible in the editor"

# Enter both clears the filter AND returns focus to the editor (mirrors
# plain-mode Enter — see _tree_open_selected's trailing set_focused(0)), so
# the DOCUMENT-context status bar (e.g. the "Save" pill) should now be
# showing instead of any FILE_TREE-context hint like "Esc clear".
qa_assert_expect "Save" "status bar switches to DOCUMENT context — Enter returned focus to the editor"
qa_assert_not_screen "Esc clear" "no FILE_TREE filter hint remains — filter mode was exited"

if echo "$QA_SCREEN" | grep -q "needle.txt"; then
    qa_pass "needle.txt tab is now active"
else
    qa_fail "needle.txt tab is now active"
fi

qa_keys "ctrl-q" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qi "unsaved\|discard\|save"; then
    qa_send "n" 0.2
fi

qa_summary
