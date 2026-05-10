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
    "This shows a text editor with multiple tabs at the top. Verify: (1) A tab bar with at least 2-3 tabs is visible at the top. (2) One tab may appear highlighted or slightly different from the others (brighter, different background). If all tabs look the same, that's a FAIL — at least one should show a hover/highlight effect." \
    "tab hover shows highlight effect"

qa_keys "ctrl-q"
qa_summary
