#!/usr/bin/env bash
# QA-XFM-009: UTF-8 preserved through transform
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-009: UTF-8 preserved through transform"

file=$(qa_tmpfile_nl "xfm009.txt" "hello world")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Transform with cat (pass-through)
qa_keys "alt-t"
qa_keys "ctrl-a" 0.1
qa_send "cat" 0.2
qa_keys "enter"
sleep 0.5

qa_assert_screen "hello world" "text preserved through cat transform"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
