#!/usr/bin/env bash
# QA-TAB-012: Tab bar scroll arrows with many tabs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-012: Tab bar scroll arrows (visual)"

# Create many files to overflow the tab bar
files=""
for i in $(seq 1 15); do
    f=$(qa_tmpfile_nl "tab012_file_$i.txt" "content $i")
    files="$files $f"
done
qa_start $files
sleep 0.5

shot="$QA_TMPDIR/tab012.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with MANY tabs open (15 files). The tab bar cannot fit all tabs. Verify: (1) Scroll arrows or overflow indicators are visible at the edges of the tab bar (left and/or right arrows like < > or similar). (2) Not all 15 tabs are shown simultaneously — some are hidden/scrolled off." \
    "Tab bar shows scroll arrows with many tabs"

qa_keys "ctrl-q"

qa_summary
