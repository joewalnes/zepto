#!/usr/bin/env bash
# QA-GUT-011: Minimap visible by default on long file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-011: Minimap visible by default (visual)"

content=""
for i in $(seq 1 150); do
    content+="def func_$i(): return $i * 2"$'\n'
done
file=$(qa_tmpfile_nl "gut011.py" "$content")
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/gut011.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a long file (150 lines). Verify: (1) A MINIMAP column is visible on the RIGHT side of the editor (a narrow 3-4 character wide strip). (2) The minimap shows a compressed/dense representation of the file content using small characters or Braille dots. (3) A VIEWPORT HIGHLIGHT (a lighter or brighter region) is visible within the minimap showing which part of the file is currently on screen." \
    "Minimap visible on right with viewport highlight"

qa_keys "ctrl-q"

qa_summary
