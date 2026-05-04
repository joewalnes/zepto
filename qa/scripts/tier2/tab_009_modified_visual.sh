#!/usr/bin/env bash
# QA-TAB-009: Modified file shows dot/indicator on tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-009: Modified file indicator on tab (visual)"

file=$(qa_tmpfile_nl "tab009.txt" "original content here")
qa_start "$file"

# Screenshot before modification
shot_clean="$QA_TMPDIR/tab_clean.png"
qa_screenshot "$shot_clean"

# Modify the file
qa_send "new text "
sleep 0.3

# Screenshot after modification
shot_dirty="$QA_TMPDIR/tab_dirty.png"
qa_screenshot "$shot_dirty"

qa_assert_visual "$shot_dirty" \
    "This shows a terminal text editor with a modified (unsaved) file. Look at the TAB BAR at the top. Verify: (1) The active tab shows a modification indicator — a dot, circle, bullet, or similar symbol near the filename indicating unsaved changes. (2) The tab displays the filename text. (3) The modification indicator is clearly visible and not just a normal part of the filename." \
    "Modified file tab shows unsaved indicator dot"

qa_keys "ctrl-q"
sleep 0.2
# Dismiss save prompt if any
qa_keys "escape"
sleep 0.2
qa_keys "ctrl-q"

qa_summary
