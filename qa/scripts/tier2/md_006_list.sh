#!/usr/bin/env bash
# QA-MD-006: Markdown list items rendered with proper indentation
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-006: Markdown list indentation (visual)"

file=$(qa_tmpfile_nl "md006.md" '# Shopping List

- Fruits
  - Apples
  - Bananas
  - Oranges
- Vegetables
  - Carrots
  - Peas
- Dairy
  - Milk
  - Cheese

1. First step
2. Second step
3. Third step')
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/md_list.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file in a terminal text editor. Verify: (1) There are bullet list items visible with nested indentation — sub-items are indented further right than their parent items. (2) Bullet markers (dots, dashes, or special bullet characters) are visible next to list items. (3) A numbered list (1, 2, 3) is visible below the bullet list. (4) The heading at the top is visually distinct from the list text (larger, bold, or different color)." \
    "Markdown lists show proper indentation and bullet markers"

qa_keys "ctrl-q"

qa_summary
