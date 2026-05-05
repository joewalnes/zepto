#!/usr/bin/env bash
# QA-GUT-008: Ruler shows cursor column badge
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-008: Ruler cursor badge (visual)"

file=$(qa_tmpfile_nl "gut008.txt" "hello world foo bar baz")
qa_start "$file"

# Move cursor to column 12
for i in $(seq 1 11); do qa_keys "right" 0.05; done
sleep 0.3

shot="$QA_TMPDIR/gut008.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a ruler row at the top (showing column numbers like 10, 20, 30...). Verify: (1) A ruler/column indicator row is visible above or near the top of the editing area. (2) Column tick marks or numbers are shown at regular intervals." \
    "ruler with column indicators visible"

qa_keys "ctrl-q"
qa_summary
