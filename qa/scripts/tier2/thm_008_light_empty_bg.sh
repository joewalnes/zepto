#!/usr/bin/env bash
# QA-THM-008: Light mode empty-line bg not jarring
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-008: Light mode empty line background (visual)"

file=$(qa_tmpfile_nl "thm008.txt" "line 1
line 2
line 3
line 4
line 5")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t"
sleep 0.3

shot="$QA_TMPDIR/thm008.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in LIGHT theme with only 5 lines of text. Look at the area BELOW the last line. Verify: (1) The empty area below the text has a LIGHT background (white or near-white). (2) There is no jarring dark or gray block filling the empty space — it blends with the editor background." \
    "Light theme empty area below text is not jarring"

qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
