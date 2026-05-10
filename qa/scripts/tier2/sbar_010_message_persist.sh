#!/usr/bin/env bash
# QA-SBAR-010: Status bar messages persist until next input
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SBAR-010: Message persistence (visual)"

file=$(qa_tmpfile_nl "sbar010.txt" "test content for save message")
qa_start "$file"

# Make a change and save to trigger a message
qa_send "x"
sleep 0.2
qa_keys "ctrl-s"
sleep 0.5

shot_msg="$QA_TMPDIR/sbar010_msg.png"
qa_screenshot "$shot_msg"

qa_assert_visual "$shot_msg" \
    "This shows a text editor that just saved a file. Look at the STATUS BAR (bottom row). Verify: (1) A save confirmation message is visible — text like 'Saved' or the filename appears in the status bar. (2) The message is clearly readable." \
    "Save message visible in status bar after save"

# Wait a few seconds — message should still be there
sleep 3

shot_persist="$QA_TMPDIR/sbar010_persist.png"
qa_screenshot "$shot_persist"

qa_assert_visual "$shot_persist" \
    "This shows the same text editor several seconds after saving. Look at the STATUS BAR (bottom row). Verify: (1) The save message is STILL visible — it has NOT auto-dismissed. The message persists until the user presses a key." \
    "Save message persists after several seconds"

qa_keys "ctrl-q"

qa_summary
