#!/usr/bin/env bash
# QA-TAB-014: Hover on tab highlights it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-014: Tab hover (visual)"

f1=$(qa_tmpfile_nl "tab014_a.txt" "aaa")
f2=$(qa_tmpfile_nl "tab014_b.txt" "bbb")
f3=$(qa_tmpfile_nl "tab014_c.txt" "ccc")
qa_start "$f1" "$f2" "$f3"

# Screenshot without hover
shot_before="$QA_TMPDIR/before.png"
qa_screenshot "$shot_before"

# Hover over tab 2 (approximate position in tab bar, row 1)
qa_hover 30 1
sleep 0.3

shot_hover="$QA_TMPDIR/hover.png"
qa_screenshot "$shot_hover"

qa_assert_visual "$shot_hover" \
    "This shows a text editor with multiple tabs at the top, with the mouse cursor currently positioned over one of the tabs. MUST be visible: (1) A tab bar with at least 2-3 tabs. (2) EXACTLY the tab under the mouse position has a visibly different background/brightness than the other, non-hovered tabs. MUST NOT be true: all tabs must NOT look identical — if every tab has the same styling with none standing out, FAIL. If the hover effect is not clearly distinguishable in the screenshot, FAIL." \
    "the hovered tab is visually distinct from its non-hovered neighbors"

qa_keys "ctrl-q"
qa_summary
