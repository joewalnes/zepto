#!/usr/bin/env bash
# QA-XFM-013: Transform command is discoverable in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-013: Transform discoverable in palette"

file=$(qa_tmpfile_nl "xfm013.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "transform" 0.3

qa_assert_screen "Transform" "Transform command found in palette"
qa_assert_screen "T" "shortcut indicator visible"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
