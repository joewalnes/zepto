#!/usr/bin/env bash
# QA-GUT-014: Click on minimap jumps document position
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-014: Minimap click jumps document (visual)"

content=""
for i in $(seq 1 200); do
    content+="line_$i = 'content for line number $i here'"$'\n'
done
file=$(qa_tmpfile_nl "gut014.py" "$content")
qa_start "$file"
sleep 0.5

# Take screenshot at top
shot_top="$QA_TMPDIR/gut014_top.png"
qa_screenshot "$shot_top"

# Click near bottom of minimap (far right column, lower area)
qa_hover 79 18
sleep 0.3

shot_after="$QA_TMPDIR/gut014_after.png"
qa_screenshot "$shot_after"

qa_assert_visual "$shot_after" \
    "This shows a text editor with 200 lines and a minimap on the right. The document should have scrolled from the top. Verify: (1) The visible line numbers in the gutter are NOT starting at line 1 — the document has scrolled down. (2) The minimap viewport highlight has moved from its initial top position." \
    "Minimap click scrolled the document"

qa_keys "ctrl-q"

qa_summary
