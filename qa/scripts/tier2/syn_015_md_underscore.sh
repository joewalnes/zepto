#!/usr/bin/env bash
# QA-SYN-015: Markdown intraword underscores not styled
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-015: Markdown underscore intraword (visual)"

file=$(qa_tmpfile_nl "syn015.md" "# Constants

The NF_CLOSE and MAX_RETRIES constants are defined.
The some_long_variable_name identifier uses underscores.

But _this is italic_ and __this is bold__.")
qa_start "$file"

shot="$QA_TMPDIR/syn015.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file. Verify: (1) Words like NF_CLOSE and MAX_RETRIES with internal underscores appear as regular identifiers (NOT italic or emphasized). (2) The heading '# Constants' is in a distinct color. (3) Text that IS meant to be italic (_this is italic_) may or may not appear italic — that's fine." \
    "intraword underscores not styled as emphasis"

qa_keys "ctrl-q"
qa_summary
