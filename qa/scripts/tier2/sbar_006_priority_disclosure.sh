#!/usr/bin/env bash
# QA-SBAR-006: Priority-based progressive disclosure of pills
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-006: Priority pill disclosure (visual)"

file=$(qa_tmpfile_nl "sbar006.txt" "test content for priority disclosure check")
qa_start "$file"

shot="$QA_TMPDIR/sbar006.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a status bar at the bottom. Verify: (1) Multiple pill-shaped buttons are visible in the status bar. (2) The leftmost pill shows cursor position (line:column). (3) The rightmost pill says 'Commands' or shows a keyboard shortcut. These high-priority pills are always present." \
    "Status bar shows high-priority pills at normal width"

qa_keys "ctrl-q"

qa_summary
