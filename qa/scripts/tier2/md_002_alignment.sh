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
    "This shows a Markdown file with a table that has alignment syntax (left, right, center columns). If the table is pretty-rendered, verify: (1) Column content appears aligned — left column flush left, right column flush right, center column centered. (2) The table has visible structure (borders or formatted cells). If shown as raw Markdown, that is acceptable but the pipe characters and alignment markers should be visible." \
    "Markdown table respects column alignment"

qa_keys "ctrl-q"

qa_summary
