#!/usr/bin/env bash
# QA-SBAR-023: Status bar shows Wrap pill active after toggle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-023: Wrap pill active state (visual)"

file=$(qa_tmpfile_nl "sbar023w.txt" "Some text content to test the wrap pill visual state in the status bar.
Another line of text here.
Third line for good measure.")
qa_start "$file"

# Toggle wrap ON
qa_keys "alt-z"
sleep 0.3

shot="$QA_TMPDIR/sbar_wrap_active.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor. Look at the status bar (bottom row). Verify: (1) A 'Wrap' pill/button is visible in the status bar. (2) The Wrap pill appears in an ACTIVE or highlighted state — it should look toggled ON (brighter color, filled background, or otherwise distinct from inactive pills). (3) The status bar contains at least 2 other pill-shaped buttons or indicators." \
    "Wrap pill shows active/highlighted state in status bar"

# Toggle wrap OFF and clean up
qa_keys "alt-z"
qa_keys "ctrl-q"

qa_summary
