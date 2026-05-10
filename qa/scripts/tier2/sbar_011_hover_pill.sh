#!/usr/bin/env bash
# QA-SBAR-011: Hover on status bar pill shows effect
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-011: Pill hover (visual)"

file=$(qa_tmpfile_nl "sbar011.txt" "hello world")
qa_start "$file"

# Screenshot without hover
shot_before="$QA_TMPDIR/before.png"
qa_screenshot "$shot_before"

# Hover over a pill in the status bar (bottom row, rightmost area for Commands pill)
qa_hover 70 24
sleep 0.3

shot_hover="$QA_TMPDIR/hover.png"
qa_screenshot "$shot_hover"

qa_assert_visual "$shot_hover" \
    "This shows a text editor. Look at the BOTTOM ROW (status bar). Verify: (1) Pill-shaped buttons are visible. (2) One pill may appear highlighted or brighter than the others due to mouse hover. If a pill shows any visual distinction (different shade, brighter text), that's a PASS." \
    "status bar pill hover effect"

qa_keys "ctrl-q"
qa_summary
