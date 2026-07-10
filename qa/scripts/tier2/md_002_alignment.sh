#!/usr/bin/env bash
# QA-MD-002: Markdown table alignment syntax respected
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-002: Table alignment (visual)"

file=$(qa_tmpfile_nl "md002.md" "# Alignment Test

| Left   | Right  | Center |
| :----- | -----: | :----: |
| aaa    |    111 |  xxx   |
| bb     |  22222 |   y    |
| cccccc |      3 |  zz    |

End of file.")
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/md002.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file with a table that has column-alignment syntax (:---, ---:, :---:  for left/right/center). MUST be visible, ALL of these: (1) The table is pretty-rendered with visible structure (box-drawing borders or clearly formatted/padded cells) — NOT raw '| text | text |' pipe-delimited source. (2) The 'Left' column's content is flush against the LEFT edge of its cell. (3) The 'Right' column's content is flush against the RIGHT edge of its cell (padded with space on the left). (4) The 'Center' column's content is centered within its cell (roughly equal padding on both sides). MUST NOT be true: the table must NOT appear as unrendered raw Markdown (visible pipe '|' and colon/dash alignment-marker characters as literal text), and columns must NOT all look left-justified with no visible difference between them. If the alignment differences are not clearly distinguishable in the screenshot, FAIL." \
    "Markdown table is pretty-rendered with left/right/center column alignment respected"

qa_keys "ctrl-q"

qa_summary
