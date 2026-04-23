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
    "This shows a Markdown file in a terminal text editor. There should be a TABLE that is pretty-rendered — NOT shown as raw Markdown source. Verify ANY of these indicators of pretty-rendering: (1) The table has visible borders made of box-drawing characters (─, │, ┌, etc.) or other line-drawing symbols. (2) The header row appears visually distinct (bold, colored, or different background). (3) Column alignment looks neat and formatted (evenly spaced cells). (4) The separator row (---) is replaced with a horizontal line. If the table appears as raw Markdown (just | and - characters with no visual formatting), that is a FAIL." \
    "Markdown table rendered with pretty formatting"

qa_keys "ctrl-q"

qa_summary
