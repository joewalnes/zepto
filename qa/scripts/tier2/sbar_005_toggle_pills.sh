#!/usr/bin/env bash
# QA-SBAR-005: Status bar toggle pills show ON/OFF visually
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-005: Status bar toggle pills (visual)"

file=$(qa_tmpfile_nl "sbar005.txt" "test content for status bar visual check
this file has a few lines
to make the editor look realistic")
qa_start "$file"

# Default state: wrap OFF, minimap ON
shot_default="$QA_TMPDIR/sbar_default.png"
qa_screenshot "$shot_default"

qa_assert_visual "$shot_default" \
    "This shows a terminal text editor. Look at the BOTTOM ROW (status bar). Verify: (1) There are pill-shaped buttons with rounded edges. (2) The rightmost pill says 'Commands' with a keyboard shortcut. (3) There is a cursor position indicator on the left (showing line:column numbers). (4) Toggle pills like 'Wrap', 'Minimap', 'Theme' may be visible depending on terminal width." \
    "status bar pills visible in default state"

# Toggle wrap ON — pill should change appearance
qa_keys "alt-z"
sleep 0.3

shot_wrap="$QA_TMPDIR/sbar_wrap_on.png"
qa_screenshot "$shot_wrap"

qa_assert_visual "$shot_wrap" \
    "This shows a terminal text editor status bar (bottom row) immediately after word wrap was toggled ON. MUST be visible: (1) A 'Wrap' or 'Word Wrap' pill/button with readable text. (2) That pill has an ACTIVE/ON appearance — a bright, filled, or colored background (e.g. blue) that makes it visually stand out from plain status-bar text, not merely legible text on the default status-bar background. MUST NOT be true: the Wrap pill must NOT look identical in styling to a plain, unhighlighted status-bar label — dim/default-background text with no distinguishing color or fill is a FAIL even if the word 'Wrap' is readable. If you cannot clearly tell the pill is in a highlighted/active state from the screenshot, FAIL." \
    "Wrap pill shows an active/highlighted appearance after being toggled on"

# Toggle wrap OFF
qa_keys "alt-z"

qa_keys "ctrl-q"

qa_summary
