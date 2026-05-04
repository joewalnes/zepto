#!/usr/bin/env bash
# QA-XFM-007: Select text, rev reverses each line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-007: Transform rev"

file=$(qa_tmpfile_nl "xfm007.txt" "hello")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
sleep 0.3

qa_keys "ctrl-a" 0.1
qa_send "rev" 0.2
qa_keys "enter"
sleep 0.5

qa_assert_screen "olleh" "rev reversed the text"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
