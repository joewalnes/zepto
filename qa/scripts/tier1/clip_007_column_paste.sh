#!/usr/bin/env bash
# QA-CLIP-007: Column copy/paste preserves rectangle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-007: Column clipboard preserves rectangle"

file=$(qa_tmpfile_nl "clip007.txt" "aaaa1111
bbbb2222
cccc3333
dddd4444")
qa_start "$file"

# Enter column mode, select first 3 rows x 4 cols
qa_keys "alt-c"
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Copy
qa_keys "ctrl-c"

# Exit column mode
qa_keys "escape"

# Move to line 4
qa_keys "ctrl-g"
qa_send "4" 0.2
qa_keys "enter"

# Paste. NOTE: "aaaa"/"bbbb"/"cccc" are the original rows 1-3 and remain on
# screen unconditionally, so grepping for them alone (as this test used to)
# would pass even if the paste did nothing at all. Assert the actual mutated
# result on line 4 instead — the pasted column's first row ("aaaa") gets
# inserted before the existing "dddd4444" content on the target line.
#
# Verified via the saved file rather than the screen: after a column paste
# near end-of-document, moving the cursor can push the viewport's horizontal
# scroll far to the right, and the tmux screen capture then shows stale
# (un-redrawn) trailing characters for that row — a separate rendering
# quirk (see bugs.md) unrelated to the paste itself. Saving and reading the
# file back is a reliable way to check the actual buffer content.
qa_keys "ctrl-v"
qa_keys "ctrl-s" 0.5

qa_assert_file_contains "$file" "^aaaadddd4444\$" "column paste inserted rectangle onto target line"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
