#!/usr/bin/env bash
# QA-GUT-005: Empty line background blends on light theme
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-005: Light theme empty line background (visual)"

file=$(qa_tmpfile_nl "gut005.txt" "line one
line two
line three")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t"
sleep 0.3

shot="$QA_TMPDIR/gut005.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in LIGHT theme with only 3 lines of text. Look at the area BELOW the last line of text. Verify: (1) The background is LIGHT (white or near-white), matching the editor area. (2) There is NO jarring dark or gray block below the text — it blends smoothly." \
    "Light theme empty area below text blends naturally"

# Switch back to dark
qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
