#!/usr/bin/env bash
# QA-SBAR-013: Column selection shows dimensions in status bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-013: Column selection dimensions in status bar (visual)"

file=$(qa_tmpfile_nl "sbar013.txt" "abcdefghij
klmnopqrst
uvwxyz1234
5678901234
abcdefghij")
qa_start "$file"

# Enter column selection mode
qa_keys "alt-c"
sleep 0.2

# Select a rectangular region: down 3 lines, right 5 columns
qa_keys "shift-down"
qa_keys "shift-down"
qa_keys "shift-down"
qa_keys "shift-right"
qa_keys "shift-right"
qa_keys "shift-right"
qa_keys "shift-right"
qa_keys "shift-right"
sleep 0.3

shot="$QA_TMPDIR/sbar_col_dims.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in column selection mode. A rectangular block of text is highlighted/selected. Verify: (1) The status bar at the bottom shows dimension information for the column selection (such as rows x columns, or a size indicator). (2) A 'COL' or column mode indicator is visible in the status bar. (3) The selected text block in the editor appears as a rectangular highlight spanning multiple lines." \
    "Column selection dimensions shown in status bar"

qa_keys "alt-c"
qa_keys "ctrl-q"

qa_summary
