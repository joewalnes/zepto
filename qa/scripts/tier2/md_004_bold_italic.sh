#!/usr/bin/env bash
# QA-MD-004: Bold and italic markdown rendered correctly
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-004: Markdown bold and italic (visual)"

file=$(qa_tmpfile_nl "md004.md" '# Formatting Test

This is **bold text** in a sentence.

This is *italic text* in a sentence.

This is ***bold and italic*** combined.

Normal text, then **bold**, then normal, then *italic*, then normal.

Here is __also bold__ with underscores.

And _also italic_ with single underscores.

Plain paragraph for comparison — no formatting at all, just regular text to see the baseline style.')
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/md_bold_italic.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file in a terminal text editor. Verify bold and italic rendering: (1) Text between **double asterisks** appears BOLD — either thicker/heavier weight, brighter color, or otherwise more prominent than surrounding text. (2) Text between *single asterisks* appears ITALIC — either slanted, different color, or otherwise visually distinct from both plain text and bold text. (3) Text between ***triple asterisks*** appears with BOTH bold and italic styling. (4) The markdown syntax characters (*, **) may or may not be hidden, but the formatted text is visually distinguishable from the 'Plain paragraph' at the bottom. (5) There are at least 2 distinct visual styles visible beyond plain text (bold and italic)." \
    "Bold and italic markdown text rendered with distinct styles"

qa_keys "ctrl-q"

qa_summary
