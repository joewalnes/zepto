#!/usr/bin/env bash
# QA-SBAR-015: Status bar extends to terminal right edge
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-015: Status bar full width (visual)"

file=$(qa_tmpfile_nl "sbar015.txt" "test content")
qa_start "$file"

shot="$QA_TMPDIR/sbar015.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor. Look at the BOTTOM ROW (status bar). Verify: (1) The status bar background color extends ALL THE WAY to the right edge of the terminal — no gap or missing column at the far right. (2) The status bar spans the full terminal width from left to right." \
    "Status bar spans full terminal width"

qa_keys "ctrl-q"

qa_summary
