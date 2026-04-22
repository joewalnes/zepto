#!/usr/bin/env bash
# QA-PAL-014: Ctrl+Space closes palette when open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-014: Ctrl+Space toggles palette"

file=$(qa_tmpfile_nl "pal014.txt" "hello")
qa_start "$file"

# Open palette
qa_keys "ctrl-space"
qa_assert_screen "FILE|EDIT|NAVIGATE|VIEW|Commands|Save|Quit" "palette open"

# Close with Ctrl+Space
qa_keys "ctrl-space"
sleep 0.3
qa_assert_screen "hello" "editor content visible"

qa_keys "ctrl-q"
qa_summary
