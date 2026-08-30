#!/usr/bin/env bash
# QA-REG-185: The FILE_TREE-context status bar degrades honestly at narrow
# widths — the ⌃B back-to-editor hint survives down to a genuinely narrow
# width (compacting from "⌃B back" to bare "⌃B" first, matching the
# full-form-then-compact-form idiom used everywhere else in this file), and
# the ⌃␣ Commands pill (the unconditional fallback signpost per
# docs/UI_GUIDELINES.md "Discoverability Contract") never disappears, even
# when the tree-specific hints have all dropped under genuine extreme
# scarcity. See bugs.md "P1: Discoverability Contract gaps" and the
# companion QA-REG-183 (the hint existing at all) / QA-REG-184 (the shared
# core-nav hint).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-185: FILE_TREE status bar hint degrades gracefully at narrow widths"

qa_project; dir="$QA_PROJECT_DIR"
echo "hello" > a.txt

qa_start a.txt
qa_assert_expect "a\.txt" "file is open"

# --- 60 cols: ⌃B back-to-editor hint still visible (this is the property
# this whole fix exists to guarantee — a first-time user narrows their
# terminal and must still be able to find their way back to the editor). ---
qa_resize_window 60 20
qa_keys "ctrl-b"
sleep 0.5
qa_assert_screen "⌃B" "60 cols: ⌃B back-to-editor hint still visible"
# ⌃␣ Commands must never drop, at any width, in any context.
qa_assert_screen "⌃␣|Commands" "60 cols: ⌃␣ Commands fallback signpost still visible"

# --- 40 cols: genuine extreme scarcity for this context (the breadcrumb +
# fixed Open/Commands pills alone already consume most of the row) — the
# tree-specific hints may honestly disappear here, but the row must not
# render garbage/truncated glyphs, must not crash, and the unconditional
# ⌃␣ Commands signpost must still be there so a user can always find "the
# place that has all shortcuts" per the Discoverability Contract. ---
qa_resize_window 40 15
sleep 0.5
qa_assert_screen "⌃␣|Commands" "40 cols: ⌃␣ Commands fallback signpost still visible even under extreme scarcity"
if qa_alive; then
    qa_pass "40 cols: editor still alive and responsive (no crash from width squeeze)"
else
    qa_fail "40 cols: editor still alive and responsive" "process died after resize to 40x15"
fi

# Back to a normal width and confirm the editor is still fully functional
# (resizing didn't wedge anything) before exiting.
qa_resize_window 80 24
sleep 0.3
qa_keys "escape"
sleep 0.3
qa_assert_screen "Save S" "Editor recovers cleanly after resize back to 80 cols"

qa_keys "ctrl-q"
qa_summary
