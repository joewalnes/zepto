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
    "This shows a text editor status bar (bottom row) with the mouse cursor currently positioned over one of the pills. MUST be visible: (1) Multiple pill-shaped buttons in the status bar. (2) EXACTLY the pill under the mouse position shows a distinct hover appearance — a brighter or different-colored background than the other, non-hovered pills next to it. MUST NOT be true: all pills must NOT look visually identical to each other — if every pill has the same background/brightness with no single pill standing out, FAIL. A hover effect that is not clearly distinguishable from the surrounding pills in the screenshot is a FAIL." \
    "the hovered status bar pill is visually distinct from its non-hovered neighbors"

qa_keys "ctrl-q"
qa_summary
