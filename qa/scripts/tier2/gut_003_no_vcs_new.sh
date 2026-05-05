#!/usr/bin/env bash
# QA-GUT-003: No VCS gutter markers on new/untitled files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-003: No VCS markers on new file (visual)"

file=$(qa_tmpfile_nl "gut003.txt" "line one
line two
line three
line four
line five")
qa_start "$file"

shot="$QA_TMPDIR/gut003.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with 5 lines of text. Look at the LEFT GUTTER area (where line numbers are). Verify: (1) There are NO colored markers (green, yellow, red bars) in the gutter next to the line numbers. (2) The gutter area is clean — just line numbers with no VCS change indicators." \
    "no VCS gutter markers on non-git file"

qa_keys "ctrl-q"
qa_summary
