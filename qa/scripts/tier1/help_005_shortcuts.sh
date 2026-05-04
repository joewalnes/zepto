#!/usr/bin/env bash
# QA-HELP-005: Search palette for common shortcuts shows results
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-005: Shortcuts in palette"

file=$(qa_tmpfile_nl "help005.txt" "hello")
qa_start "$file"

# Search for "save"
qa_keys "ctrl-space"
qa_send "save" 0.3
qa_assert_screen "[Ss]ave" "save command found in palette"
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Search for "copy"
qa_keys "ctrl-space"
qa_send "copy" 0.3
qa_assert_screen "[Cc]opy" "copy command found in palette"
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Search for "undo"
qa_keys "ctrl-space"
qa_send "undo" 0.3
qa_assert_screen "[Uu]ndo" "undo command found in palette"
qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
