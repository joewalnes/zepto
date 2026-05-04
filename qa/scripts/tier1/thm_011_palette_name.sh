#!/usr/bin/env bash
# QA-THM-011: "Theme" or "Toggle Theme" appears in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-011: Theme in palette"

file=$(qa_tmpfile_nl "thm011.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "theme" 0.3

qa_assert_screen "[Tt]heme" "theme command visible in palette"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
