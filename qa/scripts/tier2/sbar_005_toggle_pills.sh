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
    "Look at the status bar (bottom row). The 'Wrap' toggle pill should now appear highlighted/bright (ON state) compared to the previous screenshot where it was dimmed/off. Is there a visually distinct 'Wrap' or word-wrap indicator that looks 'active' or 'enabled' (brighter background than other pills)?" \
    "Wrap pill visually distinct when ON"

# Toggle wrap OFF
qa_keys "alt-z"

qa_keys "ctrl-q"

qa_summary
