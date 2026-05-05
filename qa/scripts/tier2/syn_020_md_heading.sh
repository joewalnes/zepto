#!/usr/bin/env bash
# QA-SYN-020: Markdown headings styled distinctly
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-020: Markdown headings (visual)"

file=$(qa_tmpfile_nl "syn020.md" "# Main Title

Regular paragraph text here.

## Section Two

More body text.

### Subsection

Final text.")
qa_start "$file"

shot="$QA_TMPDIR/syn020.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file. Verify: (1) Lines starting with # (headings) are in a DIFFERENT color from regular paragraph text. (2) At least 2 distinct colors are visible in the document." \
    "Markdown headings colored differently from body"

qa_keys "ctrl-q"
qa_summary
