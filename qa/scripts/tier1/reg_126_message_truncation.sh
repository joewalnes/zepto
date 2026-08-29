#!/usr/bin/env bash
# QA-REG-126: Long status messages don't corrupt the screen
#
# Bug (found while interactively testing the new "Save As" command with
# a long absolute path): a status/error message longer than the
# terminal width was never truncated in Renderer.pm's
# _render_status_bar / _render_context_status_bar. The raw message
# wrapped onto the next real terminal row, causing an actual terminal
# scroll that the app's fixed-position redraw didn't account for — the
# tab bar disappeared and the ruler/gutter showed stale, misaligned
# content afterward (visible on the very next keystroke, not just the
# frame that printed the message).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-126: Long message does not scroll/corrupt the screen"

# Build a save path longer than any reasonable terminal width (default
# hangon session is 80 cols; this path is well over that once prefixed
# with "Saved: ").
longdir="$QA_TMPDIR/a_very_long_directory_name_to_force_message_overflow_in_the_status_bar"
mkdir -p "$longdir"
file=$(qa_tmpfile_nl "reg126.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "Save As" 0.3
qa_keys "enter"
longpath="$longdir/reg126_saved.txt"
qa_send "$longpath"
qa_keys "enter"

# The message itself must be truncated (leading ellipsis), never the
# raw multi-terminal-row string.
qa_assert_expect "…" "long save message is truncated with an ellipsis"
qa_assert_expect "reg126_saved.txt" "truncated message still shows the filename (tail preserved)"

# The tab bar must still be present — this is what silently vanished
# under the bug (screen scrolled up by the overflow, taking row 1 with
# it).
qa_assert_expect "reg126_saved.txt.*⌃W" "tab bar still visible after the long message"

# Move the cursor — under the bug, the corruption was most visible on
# the NEXT redraw after the message (stale ruler/gutter row), not just
# the message frame itself.
qa_keys "right"
qa_assert_expect "reg126_saved.txt.*⌃W" "tab bar still visible after a redraw following the long message"

qa_assert_expect '\|10 *\|20 *\|30' "ruler row intact (no stale duplicate ruler line)"
qa_assert_expect "hello" "document content still visible after redraw"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
