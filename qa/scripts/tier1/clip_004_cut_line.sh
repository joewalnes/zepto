#!/usr/bin/env bash
# QA-CLIP-004: Cut with no selection removes entire line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-004: Cut line (no selection)"

file=$(qa_tmpfile_nl "clip004.txt" "delete me
keep me")
qa_start "$file"

# No selection — ctrl-x should cut entire line
qa_keys "ctrl-x"

qa_assert_not_screen "delete me" "line removed"
qa_assert_screen "keep me" "other line still present"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
