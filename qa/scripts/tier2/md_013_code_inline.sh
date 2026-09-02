#!/usr/bin/env bash
# QA-MD-013: Inline code in markdown styled
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-013: Markdown inline code (visual)"

file=$(qa_tmpfile_nl "md013.md" "# Code Examples

Use the \`print()\` function to output text.
The variable \`x\` holds the value.
Run \`make build\` to compile.

Regular paragraph without code.")
qa_start "$file"

shot="$QA_TMPDIR/md013.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file. Verify: (1) The heading '# Code Examples' is in a distinct color from body text. (2) At least 2 different colors are used in the document." \
    "Markdown with distinct heading color"

qa_keys "ctrl-q"
qa_summary
