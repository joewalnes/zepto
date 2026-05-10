#!/usr/bin/env bash
# QA-GUT-009: Ruler extends to window edge without gap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-009: Ruler extends to window edge (visual)"

file=$(qa_tmpfile_nl "gut009.txt" "short line of text")
qa_start "$file"

# Switch to light theme to make ruler edge easier to see
qa_keys "ctrl-t"
sleep 0.3

shot="$QA_TMPDIR/gut009.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in light theme. Look at the RULER BAR (the row with column numbers like 10, 20, 30 below the tab bar). Verify: (1) The ruler bar extends all the way to the RIGHT EDGE of the terminal — no gap or missing column at the far right. (2) The ruler has a consistent background color across its full width." \
    "Ruler extends to terminal right edge with no gap"

qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
