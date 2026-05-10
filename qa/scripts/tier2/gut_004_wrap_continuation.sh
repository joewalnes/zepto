#!/usr/bin/env bash
# QA-GUT-004: Wrap continuation rows show ↪ indicator in gutter
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-004: Wrap continuation indicator (visual)"

file=$(qa_tmpfile_nl "gut004.txt" "short line
This is a very long line that should wrap around to the next row when word wrap is enabled because it contains many words and keeps going and going until it definitely exceeds the terminal width completely
another short line
end")
qa_start "$file"

# Enable word wrap
qa_keys "alt-z"
sleep 0.3

shot="$QA_TMPDIR/gut004.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with word wrap ON. A long line wraps to multiple rows. Look at the LEFT GUTTER. Verify: (1) Continuation rows (wrapped parts of the long line) show a special symbol like an arrow or ↪ instead of a line number. (2) Only the first row of the wrapped line shows a line number." \
    "Wrap continuation rows show indicator in gutter"

qa_keys "alt-z"
qa_keys "ctrl-q"

qa_summary
