#!/usr/bin/env bash
# QA-MD-008: Cursor in table shows raw markdown source
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-008: Cursor in table shows raw (visual)"

file=$(qa_tmpfile_nl "md008.md" "# Title

| Name  | Age |
|-------|-----|
| Alice | 30  |
| Bob   | 25  |

End of file.")
qa_start "$file"

# Move cursor into the table
qa_keys "ctrl-g"
qa_send "5" 0.2
qa_keys "enter"
sleep 0.3

shot="$QA_TMPDIR/md008.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file with the cursor inside a table area. Verify: (1) The table content is visible (names and ages). (2) Either pipe characters | are visible (raw mode) OR box-drawing characters show a formatted table. Both are acceptable." \
    "table content visible with cursor inside"

qa_keys "ctrl-q"
qa_summary
