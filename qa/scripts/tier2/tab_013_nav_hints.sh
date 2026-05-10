#!/usr/bin/env bash
# QA-TAB-013: Tab bar navigation hints visible
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-013: Tab bar navigation hints (visual)"

f1=$(qa_tmpfile_nl "tab013_a.txt" "aaa")
f2=$(qa_tmpfile_nl "tab013_b.txt" "bbb")
qa_start "$f1" "$f2"

shot="$QA_TMPDIR/tab013.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with 2 tabs. Look at the RIGHT SIDE of the TAB BAR (top row). Verify: (1) Keyboard shortcut hints are visible on the right side of the tab bar — text showing navigation shortcuts like close, next, prev tab keys. (2) At least one shortcut hint is readable." \
    "Tab bar shows navigation hints on the right"

qa_keys "ctrl-q"

qa_summary
