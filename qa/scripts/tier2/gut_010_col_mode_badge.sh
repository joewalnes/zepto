#!/usr/bin/env bash
# QA-GUT-010: Column mode indicator appears at right of ruler
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-010: Column mode indicator on ruler (visual)"

file=$(qa_tmpfile_nl "gut010.txt" "abcdefghij
klmnopqrst
uvwxyz1234
5678901234")
qa_start "$file"

# Enter column mode
qa_keys "alt-c"
sleep 0.3

shot="$QA_TMPDIR/gut010.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in column mode. Look at the RULER BAR (second row, with column numbers). Verify: (1) A 'COL' badge or indicator is visible at the RIGHT side of the ruler bar. (2) The badge has a distinct background or style making it stand out from the ruler numbers." \
    "COL badge visible on ruler in column mode"

qa_keys "alt-c"
qa_keys "ctrl-q"

qa_summary
