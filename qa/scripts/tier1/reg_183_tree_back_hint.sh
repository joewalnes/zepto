#!/usr/bin/env bash
# QA-REG-183: The FILE_TREE-context status bar has an on-screen hint for
# ⌃B, the shortcut that switches focus back to the editor (keeping the
# tree open). Previously there was ZERO on-screen indication of this
# anywhere in the FILE_TREE context — confirmed by both the automated LLM
# vision-judge sweep and direct manual testing (see bugs.md "P1:
# Discoverability Contract gaps... FILE_TREE context is missing on-screen
# hints for... switching focus back to the editor").
# Fix: Renderer.pm::_render_context_status_bar's tree-focused hint row now
# includes a "⌃B back" pill (highest priority of the tree-context pills —
# see the ordering comment above @tree_pill_candidates), fit via the same
# _fit_pill_group() helper the DOCUMENT status bar's ⌃/⌥ pill columns use.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-183: FILE_TREE context has an on-screen ⌃B-back-to-editor hint"

qa_project; dir="$QA_PROJECT_DIR"
echo "hello" > a.txt
echo "world" > b.txt

qa_start a.txt
qa_assert_expect "a\.txt" "file is open"

# Default hangon terminal size (80 cols) is wide enough for the tree-context
# hint row to include the "⌃B back" pill.
qa_keys "ctrl-b"
sleep 0.5
qa_assert_screen "⌃B" "Tree status bar shows the ⌃B shortcut glyph"
qa_assert_screen "back" "Tree status bar labels ⌃B with 'back' (not a bare, unlabeled glyph)"

# Functional check, not just cosmetic: ⌃B must actually switch focus back
# to the editor while leaving the tree open (distinct from Esc, which
# dismisses the tree — see docs/UI_GUIDELINES.md "Navigation And Focus").
qa_keys "ctrl-b"
sleep 0.5
qa_screen
if echo "$QA_SCREEN" | grep -qE "Save S"; then
    qa_pass "⌃B actually returns focus to the editor (document-context pills reappear)"
else
    qa_fail "⌃B actually returns focus to the editor" "Document-context status bar pills not seen after ⌃B"
fi
# Tree should still be visible (⌃B toggles focus, not visibility)
if echo "$QA_SCREEN" | grep -qE "a\.txt"; then
    qa_pass "Tree panel remains open after ⌃B (focus-switch, not dismiss)"
else
    qa_fail "Tree panel remains open after ⌃B" "Tree panel appears to have closed"
fi

qa_keys "ctrl-q"
qa_summary
