#!/usr/bin/env bash
# QA-MD-007: Markdown table with aligned columns and box-drawing borders
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-007: Markdown table aligned columns (visual)"

file=$(qa_tmpfile_nl "md007.md" '# Inventory

| Item       | Qty | Price  | In Stock |
| ---------- | --- | ------ | -------- |
| Widget     | 100 | $9.99  | Yes      |
| Gadget     |  25 | $24.50 | No       |
| Doohickey  |   7 | $3.25  | Yes      |
| Thingamajig|  42 | $15.00 | Yes      |

End of table.')
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/md_table_cols.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file with a rendered table. Verify: (1) The table has visible borders made of box-drawing characters (lines, corners) — not raw pipe characters. (2) Columns are neatly aligned with consistent spacing. (3) The header row is visually distinct from data rows (different color, bold, or separator line). (4) At least 4 columns and 4 data rows are visible." \
    "Markdown table shows aligned columns with box-drawing borders"

qa_keys "ctrl-q"

qa_summary
