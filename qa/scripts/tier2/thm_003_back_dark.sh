#!/usr/bin/env bash
# QA-THM-003: Toggle back to dark theme
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-003: Toggle back to dark (visual)"

file=$(qa_tmpfile_nl "thm003.txt" "test content here")
qa_start "$file"

# Toggle to light
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
sleep 0.3

# Toggle back to dark
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
sleep 0.3

shot="$QA_TMPDIR/thm003.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor. Verify: (1) The main editing area has a DARK background. (2) Text is light on dark. This confirms the theme was toggled back to dark." \
    "theme toggled back to dark"

qa_keys "ctrl-q"
qa_summary
