#!/usr/bin/env bash
# QA-HELP-007: Embedded docs work offline (content is in the binary)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-007: Embedded docs work offline"

file=$(qa_tmpfile_nl "help007.txt" "test content")
qa_start "$file"

# Open tutorial via F1
qa_keys "f1"
sleep 0.5

# Tutorial content should render (embedded in binary)
qa_assert_screen "Zepto|Tutorial|Getting Started|Welcome|shortcut" "tutorial content embedded and rendered"

# Close tutorial tab
qa_keys "ctrl-w"

# Open changelog via palette
qa_keys "ctrl-space"
qa_send "changelog" 0.3
qa_keys "enter"
sleep 0.5

qa_assert_screen "Changelog|changelog|Changes|Fixed|Added" "changelog content embedded and rendered"

qa_keys "ctrl-w"
qa_keys "ctrl-q"
qa_summary
