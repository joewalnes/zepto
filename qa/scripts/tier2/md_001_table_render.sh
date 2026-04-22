#!/usr/bin/env bash
# QA-MD-001: Markdown table pretty-rendered with box-drawing borders
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-001: Markdown table pretty rendering (visual)"

file=$(qa_tmpfile_nl "md001.md" "# Team Directory

Some text before the table.

| Name    | Role      | Location |
| ------- | --------- | -------- |
| Alice   | Engineer  | NYC      |
| Bob     | Designer  | London   |
| Charlie | PM        | Tokyo    |

Some text after the table.")
qa_start "$file"
sleep 0.5  # extra time for markdown rendering

shot="$QA_TMPDIR/md_table.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file in a terminal text editor. There should be a TABLE rendered with box-drawing characters (continuous lines like ─, │, ┌, ┬, ├, ┼, etc.) instead of raw pipe characters. Verify: (1) The table has visible borders made of line-drawing characters (not just | and -). (2) The header row ('Name', 'Role', 'Location') appears bold or with a distinct background. (3) Data rows may have alternating stripe backgrounds for readability. (4) The text BEFORE and AFTER the table ('Some text before/after') appears as normal text, not inside the table. (5) Column alignment looks correct — text is properly spaced within cells." \
    "Markdown table rendered with box-drawing borders"

qa_keys "ctrl-q"

qa_summary
