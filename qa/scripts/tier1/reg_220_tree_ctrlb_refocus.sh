#!/usr/bin/env bash
# QA-REG-220: ⌃B refocuses the file tree (instead of hiding it) when the
# tree is visible but unfocused.
#
# Bug: bugs.md P2 "⌃B hides the tree instead of refocusing it when the
# tree is already visible-but-unfocused, contradicting
# docs/UI_GUIDELINES.md". Per docs/UI_GUIDELINES.md's "Navigation And
# Focus" section: "⌃B is context-dependent: when the file tree is hidden
# it shows the tree and focuses it; when the tree is visible it toggles
# focus between the tree and the editor." `cmd_toggle_tree` (Editor.pm)
# only ever checked whether the tree was visible, not whether it was
# focused — so from "visible but unfocused" (a real, easily-reached state:
# e.g. right after Enter opens a file from the tree, which unfocuses it
# but leaves it open) pressing ⌃B hid the tree entirely instead of
# refocusing it, silently routing subsequent keystrokes into the document.
#
# This script asserts non-tautologically: it checks for "ccc.txt", a file
# that is never opened as a tab and can therefore only ever appear on
# screen via the tree panel's own file listing — unlike checking for the
# *open* file's name, which would also appear in the tab bar regardless of
# whether the tree panel itself is visible (see bugs.md's note on
# QA-REG-183's tautological "Tree panel remains open" assertion, found
# while investigating this bug — logged separately, not fixed here).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-220: ⌃B refocuses a visible-but-unfocused tree"

qa_project; dir="$QA_PROJECT_DIR"
echo "content_aaa" > aaa.txt
echo "content_bbb" > bbb.txt
echo "content_ccc" > ccc.txt

qa_start aaa.txt

# --- Show + focus the tree from hidden ---
qa_keys "ctrl-b"
sleep 0.5
qa_assert_screen "ccc\.txt" "Tree panel visible (lists ccc.txt, never opened as a tab)"
qa_assert_screen "⌃B back" "Tree is focused (⌃B-back hint pill shown)"

# --- Open bbb.txt from the tree via Enter: this unfocuses the tree but
#     leaves it visible (the "visible-but-unfocused" state the bug is about) ---
qa_keys "down" 0.2
qa_keys "enter" 0.3
qa_assert_expect "content_bbb" "Enter opened bbb.txt in the editor"
qa_screen
if echo "$QA_SCREEN" | grep -qE "⌃B back"; then
    qa_fail "Tree should be unfocused after opening a file" "⌃B-back hint pill still present"
else
    qa_pass "Tree is unfocused after opening a file from it (precondition for the bug)"
fi
if echo "$QA_SCREEN" | grep -qE "ccc\.txt"; then
    qa_pass "Tree panel remains visible after opening a file (precondition for the bug)"
else
    qa_fail "Tree panel remains visible after opening a file" "ccc.txt not found on screen"
fi

# --- The fix under test: ⌃B from visible-but-unfocused must refocus the
#     tree, not hide it. ---
qa_keys "ctrl-b"
sleep 0.5
qa_screen
if echo "$QA_SCREEN" | grep -qE "ccc\.txt"; then
    qa_pass "Tree panel still visible after ⌃B (not hidden)"
else
    qa_fail "Tree panel still visible after ⌃B (not hidden)" "ccc.txt not found — tree was hidden instead of refocused"
fi
if echo "$QA_SCREEN" | grep -qE "⌃B back"; then
    qa_pass "Tree is refocused after ⌃B (⌃B-back hint pill reappeared)"
else
    qa_fail "Tree is refocused after ⌃B" "⌃B-back hint pill not present — tree was not refocused"
fi

# --- Functional check: with the tree focused again, typed characters
#     should NOT reach the document. ---
qa_send "Z"
sleep 0.2
qa_screen
if echo "$QA_SCREEN" | grep -qE "content_Zbbb|Zcontent_bbb"; then
    qa_fail "Typed character does not leak into the document while tree is focused" "found stray 'Z' in bbb.txt content"
else
    qa_pass "Typed character does not leak into the document while tree is focused"
fi

qa_keys "ctrl-q"
qa_summary
