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
    "This shows a Markdown file where the cursor has just been placed inside a table cell. Zepto's expected behavior is that a table reverts to its RAW Markdown source while the cursor is inside it. MUST be visible: (1) The literal pipe '|' characters delimiting table columns. (2) The row of dashes ('-------|-----' or similar) that forms the raw header-separator line. (3) The table's text content (names and ages) is still readable. MUST NOT be visible: box-drawing/line-drawing table borders (─, │, ┌, ┬, ┐, etc.) — that would mean the table is still pretty-rendered instead of having reverted to raw source. If the table still shows formatted box-drawing borders rather than raw pipe characters, FAIL." \
    "table shows raw Markdown source (pipes visible) while cursor is inside it, not pretty-rendered borders"

qa_keys "ctrl-q"
qa_summary
